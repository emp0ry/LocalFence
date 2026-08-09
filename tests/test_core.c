#include "LFCore.h"

#include <arpa/inet.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>

static uint32_t ip(const char *text) {
    uint32_t result = 0;
    assert(lf_parse_ipv4(text, &result));
    return result;
}

static void test_mac(void) {
    uint8_t mac[6] = {0};
    char text[LF_MAC_STRING_LENGTH] = {0};

    assert(lf_parse_mac("c:dc:7e:62:21:60", mac));
    lf_format_mac(mac, text);
    assert(strcmp(text, "0c:dc:7e:62:21:60") == 0);
    assert(!lf_parse_mac("aa:bb:cc:dd:ee", mac));
    assert(!lf_parse_mac("aa:bb:cc:dd:ee:1ff", mac));
}

static void test_scope(void) {
    assert(lf_is_private_ipv4(ip("10.0.0.1")));
    assert(lf_is_private_ipv4(ip("172.31.255.1")));
    assert(lf_is_private_ipv4(ip("192.168.10.16")));
    assert(!lf_is_private_ipv4(ip("8.8.8.8")));

    uint32_t local = ip("192.168.10.17");
    uint32_t gateway = ip("192.168.10.1");
    uint32_t mask = ip("255.255.255.0");
    assert(lf_is_usable_client(ip("192.168.10.16"), local, gateway, mask));
    assert(!lf_is_usable_client(local, local, gateway, mask));
    assert(!lf_is_usable_client(gateway, local, gateway, mask));
    assert(!lf_is_usable_client(ip("192.168.11.20"), local, gateway, mask));
    assert(!lf_is_usable_client(ip("192.168.10.255"), local, gateway, mask));
}

static void test_parsers(void) {
    const char *route =
        "   route to: default\n"
        "    gateway: 192.168.10.1\n"
        "  interface: en0\n";
    char gateway[LF_IPV4_STRING_LENGTH] = {0};
    char interface_name[LF_INTERFACE_NAME_LENGTH] = {0};
    assert(lf_parse_route_output(route, gateway, interface_name));
    assert(strcmp(gateway, "192.168.10.1") == 0);
    assert(strcmp(interface_name, "en0") == 0);

    char parsed_ip[LF_IPV4_STRING_LENGTH] = {0};
    uint8_t parsed_mac[6] = {0};
    assert(lf_parse_arp_line(
        "? (192.168.10.18) at c:dc:7e:62:21:60 on en0 ifscope [ethernet]",
        parsed_ip, parsed_mac, interface_name));
    assert(strcmp(parsed_ip, "192.168.10.18") == 0);
    assert(strcmp(interface_name, "en0") == 0);
    assert(!lf_parse_arp_line(
        "? (192.168.10.44) at (incomplete) on en0 ifscope [ethernet]",
        parsed_ip, parsed_mac, interface_name));
}

static void test_frame(void) {
    uint8_t phone[6] = {0x12, 0x86, 0x94, 0xde, 0x9c, 0xff};
    uint8_t client[6] = {0x26, 0x7a, 0x7a, 0xe2, 0x66, 0xf3};
    uint8_t frame[LF_ARP_FRAME_LENGTH] = {0};

    assert(lf_build_arp_frame(frame, phone, client, phone,
                              ip("192.168.10.1"), client,
                              ip("192.168.10.16"),
                              LFArpOperationRequest) == LF_ARP_FRAME_LENGTH);
    assert(memcmp(frame, client, 6) == 0);
    assert(memcmp(frame + 6, phone, 6) == 0);
    assert(frame[12] == 0x08 && frame[13] == 0x06);
    assert(frame[20] == 0x00 && frame[21] == 0x01);
    assert(memcmp(frame + 22, phone, 6) == 0);
    assert(memcmp(frame + 32, client, 6) == 0);
}

int main(void) {
    test_mac();
    test_scope();
    test_parsers();
    test_frame();
    assert(lf_valid_interval_ms(5));
    assert(lf_valid_interval_ms(10));
    assert(lf_valid_interval_ms(20));
    assert(lf_valid_interval_ms(50));
    assert(lf_valid_interval_ms(5000));
    assert(!lf_valid_interval_ms(4));
    assert(!lf_valid_interval_ms(5001));
    puts("LocalFence core tests passed");
    return 0;
}
