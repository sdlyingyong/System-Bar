/*
 * smc-probe — read-only SMC key probe (run as root).
 *
 * Verifies whether the SMC user client on this machine allows a
 * third-party (non-Apple) process to read charging-control keys
 * (CH0B/CH0C/BCLM), which the charge-limit feature needs to write.
 *
 * Read-only: sends KEY_INFO + READ_BYTES only, changes nothing.
 *
 *   sudo smc-probe CH0B BCLM CH0C
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>

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

static io_connect_t smc_conn = 0;

static uint32_t encode_key(const char *k) {
    uint32_t v = 0;
    for (int i = 0; i < 4 && k[i]; i++) v = (v << 8) | (unsigned char)k[i];
    return v;
}

static void fccs(uint32_t v, char out[5]) {
    out[0] = (v >> 24) & 0xff; out[1] = (v >> 16) & 0xff;
    out[2] = (v >> 8) & 0xff;  out[3] = v & 0xff; out[4] = 0;
}

static int smc_call(KeyData *in, int *result_out) {
    KeyData out; memset(&out, 0, sizeof(out));
    size_t out_size = sizeof(out);
    kern_return_t r = IOConnectCallStructMethod(smc_conn, KERNEL_INDEX_SMC, in,
                                                sizeof(KeyData), &out, &out_size);
    if (r != KERN_SUCCESS) {
        printf("  IOConnectCallStructMethod 失败: %#x\n", r);
        return -1;
    }
    if (result_out) *result_out = out.result;
    *in = out;
    return 0;
}

static int probe_key(const char *key) {
    KeyData d; memset(&d, 0, sizeof(d));
    d.key = encode_key(key);
    d.data8 = CMD_READ_KEYINFO;
    int result = -1;
    if (smc_call(&d, &result) != 0) return -1;
    if (result != 0) {
        printf("%-6s KEY_INFO 被拒 (result=%d)\n", key, result);
        return -1;
    }
    char t[5]; fccs(d.keyInfo.data_type, t);
    uint32_t size = d.keyInfo.data_size;

    KeyData d2; memset(&d2, 0, sizeof(d2));
    d2.key = d.key;
    d2.keyInfo = d.keyInfo;
    d2.data8 = CMD_READ_BYTES;
    if (smc_call(&d2, &result) != 0) return -1;
    if (result != 0) {
        printf("%-6s READ_BYTES 被拒 (result=%d)\n", key, result);
        return -1;
    }

    printf("%-6s 类型=%-4s 大小=%u  原始字节:", key, t, size);
    for (uint32_t i = 0; i < size && i < 16; i++) printf(" %02x", d2.bytes[i]);
    printf("\n");
    return 0;
}

static int open_smc(void) {
    /* 1) 尝试 AppleSMCKeysEndpoint 子服务（部分机型） */
    io_iterator_t iter;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSMC"), &iter) == KERN_SUCCESS) {
        io_registry_entry_t svc;
        while ((svc = IOIteratorNext(iter))) {
            char name[128] = {0};
            IORegistryEntryGetName(svc, name);
            kern_return_t r = IOServiceOpen(svc, mach_task_self(), 0, &smc_conn);
            if (r == KERN_SUCCESS) {
                printf("已打开 AppleSMC 服务: %s\n", name);
                IOObjectRelease(svc);
                IOObjectRelease(iter);
                return 0;
            }
            IOObjectRelease(svc);
        }
        IOObjectRelease(iter);
    }
    printf("无法打开任何 AppleSMC 服务\n");
    return -1;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: smc-probe KEY...\n");
        return 1;
    }
    printf("=== SMC 探测（只读，无副作用）===\n");
    if (open_smc() != 0) return 1;

    int readable = 0;
    for (int i = 1; i < argc; i++) {
        if (probe_key(argv[i]) == 0) readable++;
    }

    if (readable > 0) {
        printf("=== 结论：✅ SMC 可读 → 充电上限开关有望实现 ===\n");
    } else {
        printf("=== 结论：❌ SMC 对本进程锁死（即使 root）→ 充电上限无法实现，建议 macOS 15 自带 80%% 或 AlDente ===\n");
    }
    IOServiceClose(smc_conn);
    return readable > 0 ? 0 : 2;
}
