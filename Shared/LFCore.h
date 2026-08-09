#ifndef LF_CORE_H
#define LF_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define LF_MAC_LENGTH 6
#define LF_MAC_STRING_LENGTH 18
#define LF_IPV4_STRING_LENGTH 16
#define LF_INTERFACE_NAME_LENGTH 16
#define LF_ARP_FRAME_LENGTH 42

typedef enum {
    LFArpOperationRequest = 1,
    LFArpOperationReply = 2,
} LFArpOperation;

bool lf_parse_mac(const char *text, uint8_t result[LF_MAC_LENGTH]);
void lf_format_mac(const uint8_t mac[LF_MAC_LENGTH],
                   char result[LF_MAC_STRING_LENGTH]);
bool lf_parse_ipv4(const char *text, uint32_t *network_order_result);
bool lf_is_private_ipv4(uint32_t network_order_address);
bool lf_same_subnet(uint32_t first_network_order,
                    uint32_t second_network_order,
                    uint32_t mask_network_order);
bool lf_is_usable_client(uint32_t candidate_network_order,
                         uint32_t local_network_order,
                         uint32_t gateway_network_order,
                         uint32_t mask_network_order);
bool lf_valid_interval_ms(unsigned int interval_ms);

bool lf_parse_route_output(const char *output,
                           char gateway[LF_IPV4_STRING_LENGTH],
                           char interface_name[LF_INTERFACE_NAME_LENGTH]);
bool lf_parse_arp_line(const char *line,
                       char ip[LF_IPV4_STRING_LENGTH],
                       uint8_t mac[LF_MAC_LENGTH],
                       char interface_name[LF_INTERFACE_NAME_LENGTH]);

size_t lf_build_arp_frame(uint8_t frame[LF_ARP_FRAME_LENGTH],
                          const uint8_t ethernet_source[LF_MAC_LENGTH],
                          const uint8_t ethernet_destination[LF_MAC_LENGTH],
                          const uint8_t arp_source[LF_MAC_LENGTH],
                          uint32_t source_ip_network_order,
                          const uint8_t arp_target[LF_MAC_LENGTH],
                          uint32_t target_ip_network_order,
                          LFArpOperation operation);

#endif

