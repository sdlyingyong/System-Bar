/*
 * smctemp — Apple Silicon system metrics reader (no root).
 *
 * Reads, on a poll cadence, one line to stdout with pipe-separated key=value
 * pairs:
 *   cpu=74.1;battery=42.3;cpupct=23.5;mempct=77.4;gpupct=57.0;power=29.8;...
 *
 * Metrics:
 *   cpu      CPU temperature °C        IOHID  (pACC/eACC max, tdie fallback)
 *   battery  battery temperature °C    IOHID  (gas gauge / battery sensors)
 *   cpupct   CPU usage %               host_processor_info delta
 *   mempct   memory usage %            host_statistics64
 *   gpupct   GPU utilization %         AGXAccelerator PerformanceStatistics
 *   power    total SoC power W         IOReport Energy Model
 *   NAME=value...                      all plausible temperature sensors
 *
 * -1 marks a metric unavailable (warm-up or unsupported), the app shows "--".
 *
 * Usage:
 *   smctemp [--once] [-i SECONDS]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <dlfcn.h>
#include <mach/mach.h>
#include <sys/sysctl.h>
#include <net/if.h>
#include <net/if_mib.h>
#include <net/route.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;

#define EVENT_TYPE_TEMPERATURE 15
#define FIELD_TEMPERATURE_LEVEL (EVENT_TYPE_TEMPERATURE << 16)
#define PAGE_APPLE_VENDOR 0xFF00
#define USAGE_TEMP_SENSOR 5

/* IOKit HID function pointers (private symbols, resolved via dlsym). */
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
    void *service;
    char  name[64];
} Sensor;

static Sensor *sensors = NULL;
static int     nsensors = 0;
static CFArrayRef servicesArray = NULL;
static void *client = NULL;

/* IOReport (power) — /usr/lib/libIOReport.dylib, linked directly. */
extern void *IOReportCopyChannelsInGroup(CFStringRef group, CFStringRef subgroup,
                                         uint64_t a, uint64_t b, uint64_t c);
extern void IOReportMergeChannels(void *a, void *b, void *c);
extern void *IOReportCreateSubscription(void *driver, void *desired, void **subscribed,
                                        uint64_t channel_id, void *config);
extern void *IOReportCreateSamples(void *sub, void *subscribed, void *config);
extern void *IOReportCreateSamplesDelta(void *prev, void *cur, void *config);
extern CFStringRef IOReportChannelGetGroup(void *ch);
extern CFStringRef IOReportChannelGetChannelName(void *ch);
extern CFStringRef IOReportChannelGetUnitLabel(void *ch);
extern int64_t IOReportSimpleGetIntegerValue(void *ch, int idx);

static void *power_sub = NULL;
static void *power_subscribed = NULL;
static void *power_prev = NULL;
static struct timespec power_prev_ts = {0, 0};

static double plausible(double v) { return v >= 1.0 && v <= 125.0; }
static double plausible_die(double v) { return v >= 15.0 && v <= 125.0; }

static int keep_sensor(const char *name) {
    if (name[0] == '\0') return 0;
    if (strstr(name, "tcal")) return 0;
    return 1;
}

static double read_temp(void *svc) {
    IOHIDEventRef ev = pCopyEvent(svc, EVENT_TYPE_TEMPERATURE, 0, 0);
    if (!ev) return -1;
    double v = pGetFloat(ev, FIELD_TEMPERATURE_LEVEL);
    CFRelease(ev);
    return v;
}

/* ---- temperature sensors ---- */

static double cpu_temperature(void) {
    double core = 0, die = 0;
    for (int i = 0; i < nsensors; i++) {
        if (strncmp(sensors[i].name, "pACC", 4) == 0 ||
            strncmp(sensors[i].name, "eACC", 4) == 0) {
            double v = read_temp(sensors[i].service);
            if (plausible_die(v) && v > core) core = v;
        } else if (strstr(sensors[i].name, "tdie")) {
            double v = read_temp(sensors[i].service);
            if (plausible_die(v) && v > die) die = v;
        }
    }
    return core > 0 ? core : die;
}

static double battery_temperature(void) {
    double best = 0;
    for (int i = 0; i < nsensors; i++) {
        if (!strstr(sensors[i].name, "gas gauge") &&
            !strstr(sensors[i].name, "battery"))
            continue;
        double v = read_temp(sensors[i].service);
        if (plausible(v) && v > best) best = v;
    }
    return best > 0 ? best : -1;
}

/* ---- CPU usage via host_processor_info ---- */

static natural_t cpu_ncpu = 0;
static processor_cpu_load_info_t cpu_prev = NULL;
static mach_msg_type_number_t cpu_prev_count = 0;
static int cpu_prev_valid = 0;

static double cpu_usage(void) {
    natural_t ncpu = 0;
    processor_cpu_load_info_t cur = NULL;
    mach_msg_type_number_t count = 0;
    if (host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &ncpu,
                            (processor_info_array_t *)&cur, &count) != KERN_SUCCESS)
        return -1;
    cpu_ncpu = ncpu;
    if (!cpu_prev_valid) {
        if (cpu_prev) vm_deallocate(mach_task_self(), (vm_address_t)cpu_prev,
                                    cpu_prev_count * sizeof(processor_cpu_load_info_data_t));
        cpu_prev = cur;
        cpu_prev_count = count;
        cpu_prev_valid = 1;
        return -1;
    }
    natural_t total_d = 0, busy_d = 0;
    for (natural_t i = 0; i < ncpu; i++) {
        natural_t pt = cpu_prev[i].cpu_ticks[CPU_STATE_USER] + cpu_prev[i].cpu_ticks[CPU_STATE_SYSTEM] +
                       cpu_prev[i].cpu_ticks[CPU_STATE_NICE] + cpu_prev[i].cpu_ticks[CPU_STATE_IDLE];
        natural_t ct = cur[i].cpu_ticks[CPU_STATE_USER] + cur[i].cpu_ticks[CPU_STATE_SYSTEM] +
                       cur[i].cpu_ticks[CPU_STATE_NICE] + cur[i].cpu_ticks[CPU_STATE_IDLE];
        natural_t pb = cpu_prev[i].cpu_ticks[CPU_STATE_USER] + cpu_prev[i].cpu_ticks[CPU_STATE_SYSTEM] +
                       cpu_prev[i].cpu_ticks[CPU_STATE_NICE];
        natural_t cb = cur[i].cpu_ticks[CPU_STATE_USER] + cur[i].cpu_ticks[CPU_STATE_SYSTEM] +
                       cur[i].cpu_ticks[CPU_STATE_NICE];
        total_d += ct - pt;
        busy_d += cb - pb;
    }
    vm_deallocate(mach_task_self(), (vm_address_t)cpu_prev,
                  cpu_prev_count * sizeof(processor_cpu_load_info_data_t));
    cpu_prev = cur;
    cpu_prev_count = count;
    if (total_d == 0) return 0;
    return (double)busy_d / total_d * 100.0;
}

/* ---- memory usage via host_statistics64 ---- */

static double mem_usage(void) {
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    vm_statistics64_data_t v;
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64, (host_info64_t)&v, &count) != KERN_SUCCESS)
        return -1;
    double total = (double)v.active_count + v.inactive_count + v.wire_count +
                   v.free_count + v.compressor_page_count;
    double used = (double)v.active_count + v.wire_count + v.compressor_page_count;
    if (total <= 0) return -1;
    return used / total * 100.0;
}

/* ---- GPU usage via AGXAccelerator ---- */

static double gpu_usage(void) {
    io_iterator_t iter;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AGXAccelerator"), &iter) != KERN_SUCCESS)
        return -1;
    io_registry_entry_t svc = IOIteratorNext(iter);
    IOObjectRelease(iter);
    if (!svc) return -1;
    CFTypeRef stats = IORegistryEntryCreateCFProperty(svc, CFSTR("PerformanceStatistics"),
                                                      kCFAllocatorDefault, 0);
    IOObjectRelease(svc);
    if (!stats || CFGetTypeID(stats) != CFDictionaryGetTypeID()) {
        if (stats) CFRelease(stats);
        return -1;
    }
    CFTypeRef v = CFDictionaryGetValue((CFDictionaryRef)stats, CFSTR("Device Utilization %"));
    double pct = -1;
    if (v && CFGetTypeID(v) == CFNumberGetTypeID())
        CFNumberGetValue((CFNumberRef)v, kCFNumberDoubleType, &pct);
    CFRelease(stats);
    return pct;
}

/* ---- power via IOReport Energy Model ---- */

static int power_init(void) {
    CFStringRef group = CFSTR("Energy Model");
    void *channels = IOReportCopyChannelsInGroup(group, NULL, 0, 0, 0);
    if (!channels) return -1;
    power_sub = IOReportCreateSubscription(NULL, channels, &power_subscribed, 0, NULL);
    CFRelease(channels);
    if (!power_sub || !power_subscribed) return -1;
    return 0;
}

static double power_watts(double dt_sec) {
    void *cur = IOReportCreateSamples(power_sub, power_subscribed, NULL);
    if (!cur) return -1;
    if (!power_prev) {
        power_prev = cur;
        power_prev_ts.tv_sec = 0;
        return -1;
    }
    void *delta = IOReportCreateSamplesDelta(power_prev, cur, NULL);
    if (power_prev) CFRelease(power_prev);
    power_prev = cur;
    if (!delta || dt_sec <= 0) return -1;

    CFArrayRef arr = (CFArrayRef)CFDictionaryGetValue((CFDictionaryRef)delta, CFSTR("IOReportChannels"));
    /* macmon 口径: all_power = CPU Energy + GPU Energy + ANE (SoC) */
    double total = 0;
    double cpu_total = 0, cpu_cluster = 0, gpu = 0, ane = 0;
    if (arr) {
        CFIndex n = CFArrayGetCount(arr);
        for (CFIndex i = 0; i < n; i++) {
            void *ch = (void *)CFArrayGetValueAtIndex(arr, i);
            CFStringRef grp = IOReportChannelGetGroup(ch);
            if (!grp || CFStringCompare(grp, CFSTR("Energy Model"), 0) != kCFCompareEqualTo)
                continue;
            CFStringRef name = IOReportChannelGetChannelName(ch);
            if (!name) continue;
            char nbuf[64] = {0};
            CFStringGetCString(name, nbuf, sizeof(nbuf), kCFStringEncodingUTF8);
            CFStringRef unit = IOReportChannelGetUnitLabel(ch);
            char ubuf[16] = {0};
            if (unit) CFStringGetCString(unit, ubuf, sizeof(ubuf), kCFStringEncodingUTF8);
            int64_t val = IOReportSimpleGetIntegerValue(ch, 0);
            double per_sec = (double)val / dt_sec;
            double w = 0;
            if (strcmp(ubuf, "mJ") == 0) w = per_sec / 1e3;
            else if (strcmp(ubuf, "uJ") == 0) w = per_sec / 1e6;
            else if (strcmp(ubuf, "nJ") == 0) w = per_sec / 1e9;

            /* Only authoritative totals count; per-core, cluster and DTL
             * channels are subsets of "CPU Energy" and would double-count. */
            if (strcmp(nbuf, "CPU Energy") == 0) cpu_total += w;
            else if (strcmp(nbuf, "PCPU") == 0 || strcmp(nbuf, "ECPU") == 0) cpu_cluster += w;
            else if (strcmp(nbuf, "GPU Energy") == 0) gpu += w;
            else if (strncmp(nbuf, "ANE", 3) == 0) ane += w;
        }
    }
    total += (cpu_total > 0 ? cpu_total : cpu_cluster) + gpu + ane;
    CFRelease(delta);
    return total;
}

/* ---- setup ---- */

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

    power_init();
    return 0;
}

/* ---- network speeds via sysctl interface counters (en* deltas) ---- */

static uint64_t net_prev_ib = 0, net_prev_ob = 0;
static int net_prev_valid = 0;

static int read_if_totals(uint64_t *ib, uint64_t *ob) {
    int mib[6] = {CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0};
    size_t len = 0;
    if (sysctl(mib, 6, NULL, &len, NULL, 0) != 0) return -1;
    char *buf = malloc(len);
    if (!buf) return -1;
    if (sysctl(mib, 6, buf, &len, NULL, 0) != 0) { free(buf); return -1; }

    uint64_t ib_ = 0, ob_ = 0;
    char *p = buf;
    while (p < buf + len) {
        struct if_msghdr *msgh = (struct if_msghdr *)p;
        if (msgh->ifm_type == RTM_IFINFO2) {
            struct if_msghdr2 *m2 = (struct if_msghdr2 *)msgh;
            char name[IFNAMSIZ] = {0};
            if_indextoname(msgh->ifm_index, name);
            if (strncmp(name, "en", 2) == 0) {
                ib_ += m2->ifm_data.ifi_ibytes;
                ob_ += m2->ifm_data.ifi_obytes;
            }
        }
        p += msgh->ifm_msglen;
    }
    free(buf);
    *ib = ib_;
    *ob = ob_;
    return 0;
}

// Returns -1 on first call (warm-up); else 0 with B/s in *down/*up.
static int net_speeds(double dt_sec, double *down, double *up) {
    uint64_t ib = 0, ob = 0;
    if (read_if_totals(&ib, &ob) != 0) return -1;
    if (!net_prev_valid) {
        net_prev_ib = ib;
        net_prev_ob = ob;
        net_prev_valid = 1;
        return -1;
    }
    if (dt_sec <= 0) return -1;
    *down = (double)(ib - net_prev_ib) / dt_sec;
    *up = (double)(ob - net_prev_ob) / dt_sec;
    net_prev_ib = ib;
    net_prev_ob = ob;
    return 0;
}

/* ---- battery health via AppleSmartBattery IORegistry ---- */

static double battery_prop(const char *key) {
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"));
    if (!svc) return -1;
    CFStringRef ks = CFStringCreateWithCString(kCFAllocatorDefault, key, kCFStringEncodingUTF8);
    CFTypeRef v = IORegistryEntryCreateCFProperty(svc, ks, kCFAllocatorDefault, 0);
    CFRelease(ks);
    IOObjectRelease(svc);
    if (!v || CFGetTypeID(v) != CFNumberGetTypeID()) {
        if (v) CFRelease(v);
        return -1;
    }
    double out = 0;
    CFNumberGetValue((CFNumberRef)v, kCFNumberDoubleType, &out);
    CFRelease(v);
    return out;
}

/* cycle count + health % (current max capacity / design capacity). */
static void battery_health(double *cycles, double *health) {
    *cycles = battery_prop("CycleCount");
    double design = battery_prop("DesignCapacity");
    double cur = battery_prop("AppleRawMaxCapacity");
    if (design > 0 && cur >= 0) *health = cur / design * 100.0;
    else *health = -1;
}

/* 剩余可用分钟 = 当前容量(mAh) / 放电电流(mA) * 60；充电/插电时 -1。 */
static double battery_remain_minutes(void) {
    double cap = battery_prop("AppleRawCurrentCapacity");
    double amp = battery_prop("Amperage");
    if (cap <= 0 || amp >= 0) return -1;
    return cap / (-amp) * 60.0;
}

/* ---- disk speeds via IOBlockStorageDriver Statistics + free space ---- */

#include <sys/statvfs.h>

static uint64_t disk_prev_r = 0, disk_prev_w = 0;
static int disk_prev_valid = 0;

static int read_disk_totals(uint64_t *r, uint64_t *w) {
    io_iterator_t iter;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iter) != KERN_SUCCESS)
        return -1;
    uint64_t r_ = 0, w_ = 0;
    io_registry_entry_t svc;
    while ((svc = IOIteratorNext(iter))) {
        CFTypeRef stats = IORegistryEntryCreateCFProperty(svc, CFSTR("Statistics"), kCFAllocatorDefault, 0);
        IOObjectRelease(svc);
        if (!stats || CFGetTypeID(stats) != CFDictionaryGetTypeID()) { if (stats) CFRelease(stats); continue; }
        CFTypeRef br = CFDictionaryGetValue((CFDictionaryRef)stats, CFSTR("Bytes (Read)"));
        CFTypeRef bw = CFDictionaryGetValue((CFDictionaryRef)stats, CFSTR("Bytes (Write)"));
        double dr = 0, dw = 0;
        if (br && CFGetTypeID(br) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)br, kCFNumberDoubleType, &dr);
        if (bw && CFGetTypeID(bw) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)bw, kCFNumberDoubleType, &dw);
        r_ += (uint64_t)dr;
        w_ += (uint64_t)dw;
        CFRelease(stats);
    }
    IOObjectRelease(iter);
    *r = r_; *w = w_;
    return 0;
}

// Returns -1 on first call (warm-up); else 0 with B/s in *rd/*wr.
static int disk_speeds(double dt_sec, double *rd, double *wr) {
    uint64_t r = 0, w = 0;
    if (read_disk_totals(&r, &w) != 0) return -1;
    if (!disk_prev_valid) {
        disk_prev_r = r;
        disk_prev_w = w;
        disk_prev_valid = 1;
        return -1;
    }
    if (dt_sec <= 0) return -1;
    *rd = (double)(r - disk_prev_r) / dt_sec;
    *wr = (double)(w - disk_prev_w) / dt_sec;
    disk_prev_r = r;
    disk_prev_w = w;
    return 0;
}

static double disk_free(void) {
    struct statvfs s;
    if (statvfs("/", &s) != 0) return -1;
    return (double)s.f_bavail * s.f_frsize;
}

/* ---- memory pressure (1=正常 2=警告 4=严重) ---- */

static double mem_pressure_level(void) {
    int level = 0;
    size_t len = sizeof(level);
    if (sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &len, NULL, 0) != 0) return -1;
    return (double)level;
}

/* ---- sampling ---- */

static void sample(void) {
    char buf[16384];
    size_t off = 0;

    double cpu = cpu_temperature();
    double battery = battery_temperature();
    double cpupct = cpu_usage();
    double mempct = mem_usage();
    double gpupct = gpu_usage();

    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    double dt_sec = 0;
    if (power_prev_ts.tv_sec) {
        dt_sec = (double)(now.tv_sec - power_prev_ts.tv_sec) +
                 (double)(now.tv_nsec - power_prev_ts.tv_nsec) / 1e9;
    }
    double power = power_watts(dt_sec);
    power_prev_ts = now;

    double down = -1, up = -1;
    net_speeds(dt_sec, &down, &up);

    double cycles = -1, health = -1;
    battery_health(&cycles, &health);
    double remain = battery_remain_minutes();
    double mempres = mem_pressure_level();

    double dread = -1, dwrite = -1;
    disk_speeds(dt_sec, &dread, &dwrite);
    double dfree = disk_free();

#define EMIT(key, val) do { \
        int m = snprintf(buf + off, sizeof(buf) - off, "%s%s=%.1f", off ? ";" : "", key, val); \
        if (m > 0) off += (size_t)m; \
    } while (0)

    EMIT("cpu", cpu);
    EMIT("battery", battery);
    EMIT("cpupct", cpupct);
    EMIT("mempct", mempct);
    EMIT("gpupct", gpupct);
    EMIT("power", power);
    EMIT("down", down);
    EMIT("up", up);
    EMIT("batcyc", cycles);
    EMIT("bathealth", health);
    EMIT("batremain", remain);
    EMIT("mempres", mempres);
    EMIT("diskread", dread);
    EMIT("diskwrite", dwrite);
    EMIT("diskfree", dfree);

    for (int i = 0; i < nsensors; i++) {
        double v = read_temp(sensors[i].service);
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
