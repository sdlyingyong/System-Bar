/*
 * smctemp — Apple Silicon CPU temperature reader via the HID event system.
 *
 * Reads named temperature sensors exposed by AppleSMC-backed HID services
 * (e.g. "PMU tdie1", "pACC MTR Temp Sensor4") without root, the same way
 * Stats / iStat / mxmon do. The IOHID entry points used here are private
 * symbols, so they are resolved with dlsym at runtime.
 *
 * Usage:
 *   smctemp            run forever, printing one line per poll interval
 *   smctemp -i 5       poll every 5 seconds (default 2)
 *   smctemp --once     print a single sample and exit
 *
 * Output (one line per poll), pipe-separated key=value pairs:
 *   cpu=68.8;PMU tdie1=68.8;pACC MTR Temp Sensor4=86.4;...
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dlfcn.h>
#include <CoreFoundation/CoreFoundation.h>

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;

#define EVENT_TYPE_TEMPERATURE 15
#define FIELD_TEMPERATURE_LEVEL (EVENT_TYPE_TEMPERATURE << 16)
#define PAGE_APPLE_VENDOR 0xFF00
#define USAGE_TEMP_SENSOR 5

/* IOKit function pointers (resolved via dlsym). */
typedef void *(*CreateFn)(CFAllocatorRef);
typedef int (*SetMatchingFn)(void *, CFDictionaryRef);
typedef CFArrayRef (*CopyServicesFn)(void *);
typedef CFTypeRef (*CopyPropertyFn)(void *, CFStringRef);
typedef IOHIDEventRef (*CopyEventFn)(void *, long, int, int);
typedef double (*GetFloatFn)(IOHIDEventRef, uint32_t);

static CreateFn      pCreate;
static SetMatchingFn pSetMatching;
static CopyServicesFn pCopyServices;
static CopyPropertyFn pCopyProperty;
static CopyEventFn   pCopyEvent;
static GetFloatFn    pGetFloat;

typedef struct {
    void *service;      /* borrowed from the services array (kept alive) */
    char  name[64];
} Sensor;

static Sensor *sensors = NULL;
static int     nsensors = 0;
static CFArrayRef servicesArray = NULL;
static void *client = NULL;

/* A reading is only plausible as a temperature in this band. */
static int plausible(double v) { return v >= 1.0 && v <= 125.0; }

/* CPU die/core sensors sit in a tighter band. */
static int plausible_die(double v) { return v >= 15.0 && v <= 125.0; }

/* Should this sensor be surfaced? Drop calibration reference channels. */
static int keep_sensor(const char *name) {
    if (name[0] == '\0') return 0;
    if (strstr(name, "tcal")) return 0;
    return 1;
}

/* CPU temperature: max over P-core (pACC) and E-core (eACC) sensors,
 * falling back to die sensors (tdie). */
static double cpu_temperature(void) {
    double core = 0, die = 0;
    for (int i = 0; i < nsensors; i++) {
        if (strncmp(sensors[i].name, "pACC", 4) == 0 ||
            strncmp(sensors[i].name, "eACC", 4) == 0) {
            IOHIDEventRef ev = pCopyEvent(sensors[i].service, EVENT_TYPE_TEMPERATURE, 0, 0);
            if (ev) {
                double v = pGetFloat(ev, FIELD_TEMPERATURE_LEVEL);
                CFRelease(ev);
                if (plausible_die(v) && v > core) core = v;
            }
        } else if (strstr(sensors[i].name, "tdie")) {
            IOHIDEventRef ev = pCopyEvent(sensors[i].service, EVENT_TYPE_TEMPERATURE, 0, 0);
            if (ev) {
                double v = pGetFloat(ev, FIELD_TEMPERATURE_LEVEL);
                CFRelease(ev);
                if (plausible_die(v) && v > die) die = v;
            }
        }
    }
    return core > 0 ? core : die;
}

static int setup(void) {
    void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
    if (!iokit) { fprintf(stderr, "smctemp: cannot load IOKit\n"); return -1; }
    pCreate       = (CreateFn)dlsym(iokit, "IOHIDEventSystemClientCreate");
    pSetMatching  = (SetMatchingFn)dlsym(iokit, "IOHIDEventSystemClientSetMatching");
    pCopyServices = (CopyServicesFn)dlsym(iokit, "IOHIDEventSystemClientCopyServices");
    pCopyProperty = (CopyPropertyFn)dlsym(iokit, "IOHIDServiceClientCopyProperty");
    pCopyEvent    = (CopyEventFn)dlsym(iokit, "IOHIDServiceClientCopyEvent");
    pGetFloat     = (GetFloatFn)dlsym(iokit, "IOHIDEventGetFloatValue");
    if (!pCreate || !pCopyEvent || !pCopyProperty || !pCopyServices ||
        !pSetMatching || !pGetFloat) {
        fprintf(stderr, "smctemp: IOHID symbols not available\n");
        return -1;
    }

    client = pCreate(kCFAllocatorDefault);
    if (!client) { fprintf(stderr, "smctemp: cannot create HID client\n"); return -1; }

    CFMutableDictionaryRef matching = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    int page = PAGE_APPLE_VENDOR, usage = USAGE_TEMP_SENSOR;
    CFNumberRef np = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &page);
    CFNumberRef nu = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &usage);
    CFDictionarySetValue(matching, CFSTR("PrimaryUsagePage"), np);
    CFDictionarySetValue(matching, CFSTR("PrimaryUsage"), nu);
    CFRelease(np); CFRelease(nu);
    pSetMatching(client, matching);
    CFRelease(matching);

    servicesArray = pCopyServices(client);
    if (!servicesArray) { fprintf(stderr, "smctemp: no HID services\n"); return -1; }

    CFIndex count = CFArrayGetCount(servicesArray);
    sensors = calloc((size_t)count, sizeof(Sensor));
    if (!sensors) return -1;
    for (CFIndex i = 0; i < count; i++) {
        void *svc = (void *)CFArrayGetValueAtIndex(servicesArray, i);
        CFTypeRef product = pCopyProperty(svc, CFSTR("Product"));
        if (!product) continue;
        if (CFGetTypeID(product) == CFStringGetTypeID()) {
            CFStringGetCString((CFStringRef)product, sensors[nsensors].name,
                               sizeof(sensors[nsensors].name), kCFStringEncodingUTF8);
        }
        CFRelease(product);
        if (keep_sensor(sensors[nsensors].name)) {
            sensors[nsensors].service = svc;
            nsensors++;
        }
    }
    return 0;
}

static void sample(void) {
    double cpu = cpu_temperature();
    char buf[8192];
    size_t off = 0;
    int n = snprintf(buf, sizeof(buf), "cpu=%.1f", cpu);
    if (n > 0) off = (size_t)n;
    for (int i = 0; i < nsensors; i++) {
        IOHIDEventRef ev = pCopyEvent(sensors[i].service, EVENT_TYPE_TEMPERATURE, 0, 0);
        if (!ev) continue;
        double v = pGetFloat(ev, FIELD_TEMPERATURE_LEVEL);
        CFRelease(ev);
        if (!plausible(v)) continue;
        int m = snprintf(buf + off, sizeof(buf) - off, ";%s=%.1f", sensors[i].name, v);
        if (m > 0) off += (size_t)m;
        if (off > sizeof(buf) - 128) break;
    }
    printf("%s\n", buf);
    fflush(stdout);
}

int main(int argc, char **argv) {
    int once = 0, interval = 2;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--once") == 0) once = 1;
        else if (strcmp(argv[i], "-i") == 0 && i + 1 < argc) interval = atoi(argv[++i]);
    }
    if (interval < 1) interval = 1;

    if (setup() != 0) return 1;
    for (;;) {
        sample();
        if (once) break;
        sleep(interval);
    }
    return 0;
}
