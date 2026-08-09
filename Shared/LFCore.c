#include "LFCore.h"

#include <arpa/inet.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static bool copy_token(const char *start, const char *end, char *result,
                       size_t capacity) {
    if (start == NULL || end == NULL || end <= start || capacity == 0) {
        return false;
    }

    size_t length = (size_t)(end - start);
    if (length >= capacity) {
        return false;
    }

    memcpy(result, start, length);
    result[length] = '\0';
    return true;
}

bool lf_parse_mac(const char *text, uint8_t result[LF_MAC_LENGTH]) {
    if (text == NULL || result == NULL) {
        return false;
    }

    unsigned int octets[LF_MAC_LENGTH] = {0};
    char trailing = '\0';
    int count = sscanf(text, "%x:%x:%x:%x:%x:%x%c", &octets[0], &octets[1],
                       &octets[2], &octets[3], &octets[4], &octets[5],
                       &trailing);
    if (count != 6) {
        return false;
    }

    for (size_t index = 0; index < LF_MAC_LENGTH; index++) {
        if (octets[index] > 0xffU) {
            return false;
        }
        result[index] = (uint8_t)octets[index];
    }

    return true;
}

void lf_format_mac(const uint8_t mac[LF_MAC_LENGTH],
                   char result[LF_MAC_STRING_LENGTH]) {
    snprintf(result, LF_MAC_STRING_LENGTH, "%02x:%02x:%02x:%02x:%02x:%02x",
             mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
}

bool lf_parse_ipv4(const char *text, uint32_t *network_order_result) {
    if (text == NULL || network_order_result == NULL) {
        return false;
    }

    struct in_addr address = {0};
    if (inet_pton(AF_INET, text, &address) != 1) {
        return false;
    }

    *network_order_result = address.s_addr;
    return true;
}

bool lf_is_private_ipv4(uint32_t network_order_address) {
    uint32_t address = ntohl(network_order_address);

    return (address & 0xff000000U) == 0x0a000000U ||
           (address & 0xfff00000U) == 0xac100000U ||
           (address & 0xffff0000U) == 0xc0a80000U;
}

bool lf_same_subnet(uint32_t first_network_order,
                    uint32_t second_network_order,
                    uint32_t mask_network_order) {
    return (first_network_order & mask_network_order) ==
           (second_network_order & mask_network_order);
}

bool lf_is_usable_client(uint32_t candidate_network_order,
                         uint32_t local_network_order,
                         uint32_t gateway_network_order,
                         uint32_t mask_network_order) {
    if (!lf_is_private_ipv4(candidate_network_order) ||
        !lf_same_subnet(candidate_network_order, local_network_order,
                        mask_network_order) ||
        candidate_network_order == local_network_order ||
        candidate_network_order == gateway_network_order) {
        return false;
    }

    uint32_t candidate = ntohl(candidate_network_order);
    uint32_t local = ntohl(local_network_order);
    uint32_t mask = ntohl(mask_network_order);
    uint32_t network = local & mask;
    uint32_t broadcast = network | ~mask;

    return candidate != network && candidate != broadcast;
}

bool lf_valid_interval_ms(unsigned int interval_ms) {
    return interval_ms >= 5U && interval_ms <= 5000U;
}

static bool value_after_label(const char *output, const char *label,
                              char *result, size_t capacity) {
    const char *position = strstr(output, label);
    if (position == NULL) {
        return false;
    }

    position += strlen(label);
    while (*position != '\0' && isspace((unsigned char)*position)) {
        position++;
    }

    const char *end = position;
    while (*end != '\0' && !isspace((unsigned char)*end)) {
        end++;
    }

    return copy_token(position, end, result, capacity);
}

bool lf_parse_route_output(const char *output,
                           char gateway[LF_IPV4_STRING_LENGTH],
                           char interface_name[LF_INTERFACE_NAME_LENGTH]) {
    if (output == NULL || gateway == NULL || interface_name == NULL ||
        !value_after_label(output, "gateway:", gateway,
                           LF_IPV4_STRING_LENGTH) ||
        !value_after_label(output, "interface:", interface_name,
                           LF_INTERFACE_NAME_LENGTH)) {
        return false;
    }

    uint32_t parsed_gateway = 0;
    return lf_parse_ipv4(gateway, &parsed_gateway) &&
           interface_name[0] != '\0';
}

bool lf_parse_arp_line(const char *line, char ip[LF_IPV4_STRING_LENGTH],
                       uint8_t mac[LF_MAC_LENGTH],
                       char interface_name[LF_INTERFACE_NAME_LENGTH]) {
    if (line == NULL || ip == NULL || mac == NULL || interface_name == NULL) {
        return false;
    }

    const char *ip_start = strchr(line, '(');
    const char *ip_end = ip_start == NULL ? NULL : strchr(ip_start + 1, ')');
    const char *mac_start = ip_end == NULL ? NULL : strstr(ip_end, " at ");
    if (mac_start == NULL) {
        return false;
    }
    mac_start += 4;
    const char *mac_end = strchr(mac_start, ' ');
    const char *interface_start = mac_end == NULL ? NULL : strstr(mac_end, " on ");
    if (interface_start == NULL) {
        return false;
    }
    interface_start += 4;
    const char *interface_end = strchr(interface_start, ' ');
    if (interface_end == NULL) {
        interface_end = interface_start + strlen(interface_start);
    }

    char mac_text[LF_MAC_STRING_LENGTH] = {0};
    if (!copy_token(ip_start + 1, ip_end, ip, LF_IPV4_STRING_LENGTH) ||
        !copy_token(mac_start, mac_end, mac_text, sizeof(mac_text)) ||
        !copy_token(interface_start, interface_end, interface_name,
                    LF_INTERFACE_NAME_LENGTH) ||
        !lf_parse_mac(mac_text, mac)) {
        return false;
    }

    uint32_t parsed_ip = 0;
    return lf_parse_ipv4(ip, &parsed_ip);
}

static void write_u16(uint8_t *destination, uint16_t host_order_value) {
    uint16_t network_order_value = htons(host_order_value);
    memcpy(destination, &network_order_value, sizeof(network_order_value));
}

size_t lf_build_arp_frame(uint8_t frame[LF_ARP_FRAME_LENGTH],
                          const uint8_t ethernet_source[LF_MAC_LENGTH],
                          const uint8_t ethernet_destination[LF_MAC_LENGTH],
                          const uint8_t arp_source[LF_MAC_LENGTH],
                          uint32_t source_ip_network_order,
                          const uint8_t arp_target[LF_MAC_LENGTH],
                          uint32_t target_ip_network_order,
                          LFArpOperation operation) {
    if (frame == NULL || ethernet_source == NULL ||
        ethernet_destination == NULL || arp_source == NULL ||
        arp_target == NULL ||
        (operation != LFArpOperationRequest &&
         operation != LFArpOperationReply)) {
        return 0;
    }

    memset(frame, 0, LF_ARP_FRAME_LENGTH);
    memcpy(frame, ethernet_destination, 6);
    memcpy(frame + 6, ethernet_source, 6);
    write_u16(frame + 12, 0x0806);

    write_u16(frame + 14, 1);
    write_u16(frame + 16, 0x0800);
    frame[18] = 6;
    frame[19] = 4;
    write_u16(frame + 20, (uint16_t)operation);
    memcpy(frame + 22, arp_source, 6);
    memcpy(frame + 28, &source_ip_network_order, 4);
    memcpy(frame + 32, arp_target, 6);
    memcpy(frame + 38, &target_ip_network_order, 4);

    return LF_ARP_FRAME_LENGTH;
}
