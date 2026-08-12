/*
 * menutemp-powerd — root daemon that reads the SMC PSTR key (total system
 * power, whole machine incl. display) and writes it to /tmp/menutemp_power.
 *
 * Must run as root: the AppleSMC user client denies key reads to unprivileged
 * processes (result 133).
 *
 *   menutemp-powerd [-i SECONDS] [--once]
 *
 * Writes: /tmp/menutemp_power  ->  "power=<watts>\n"  (-1 when unreadable)
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>

#define POWER_FILE "/tmp/menutemp_power"

typedef struct {
    uint32_t key;
    struct { uint8_t major, minor, build, reserved; uint16_t release; } vers;
    struct { uint16_t version; uint16_t length; uint32_t cpu_p_limit; uint32_t gpu_p_limit; uint32_t mem_p_limit; } pLimit;
    struct { uint32_t data_size; uint32_t data_type; uint8_t data_attributes; } keyInfo;
    uint8_t result, status, data8;
    uint32_t data32;
    uint8_t bytes[32];
} KeyData;

#define KERNEL_INDEX_SMC 2
#define CMD_READ_BYTES 5
#define CMD_READ_KEYINFO 9
#define RESULT_KEY_NOT_FOUND 132

static uint32_t encode_key(const char *k) {
    uint32_t v = 0;
    for (int i = 0; i < 4 && k[i]; i++) v = (v << 8) | (unsigned char)k[i];
    return v;
}

static io_connect_t smc_conn = 0;

static int open_smc(void) {
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) return -1;
    kern_return_t r = IOServiceOpen(svc, mach_task_self(), 0, &smc_conn);
    IOObjectRelease(svc);
    return r == KERN_SUCCESS ? 0 : -1;
}

static int smc_call(KeyData *in) {
    KeyData out; memset(&out, 0, sizeof(out));
    size_t out_size = sizeof(out);
    kern_return_t r = IOConnectCallStructMethod(smc_conn, KERNEL_INDEX_SMC, in,
                                                sizeof(KeyData), &out, &out_size);
    if (r != KERN_SUCCESS) return -1;
    if (out.result == RESULT_KEY_NOT_FOUND || out.result != 0) return -1;
    *in = out;
    return 0;
}

static int read_pstr(float *out) {
    KeyData d; memset(&d, 0, sizeof(d));
    d.key = encode_key("PSTR");
    d.data8 = CMD_READ_KEYINFO;
    if (smc_call(&d) != 0) return -1;
    if (d.keyInfo.data_size != 4) return -1;
    KeyData d2; memset(&d2, 0, sizeof(d2));
    d2.key = d.key;
    d2.keyInfo = d.keyInfo;
    d2.data8 = CMD_READ_BYTES;
    if (smc_call(&d2) != 0) return -1;
    memcpy(out, d2.bytes, 4);
    return 0;
}

static void write_power(double w) {
    FILE *f = fopen(POWER_FILE, "w");
    if (!f) return;
    fprintf(f, "power=%.1f\n", w);
    fclose(f);
}

int main(int argc, char **argv) {
    int once = 0, interval = 2;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--once") == 0) once = 1;
        else if (strcmp(argv[i], "-i") == 0 && i + 1 < argc) interval = atoi(argv[++i]);
    }
    if (interval < 1) interval = 1;

    if (open_smc() != 0) {
        write_power(-1);
        if (once) { printf("power=-1\n"); return 1; }
        return 1;
    }

    for (;;) {
        float w = -1;
        if (read_pstr(&w) == 0 && w >= 0 && w < 300) {
            write_power(w);
            if (once) { printf("power=%.1f\n", w); break; }
        } else {
            write_power(-1);
            if (once) { printf("power=-1\n"); break; }
        }
        sleep(interval);
    }
    return 0;
}
