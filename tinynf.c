#include "net/network.h"
#include "os/memory.h"
#include "os/pci.h"
#include "util/log.h"
#include "util/parse.h"


static uint16_t tinynf_packet_handler(uint8_t* packet, uint16_t packet_length, bool* send_list)
{
//	for (uint64_t n = 0; n < packet_length; n++) {
//		printf("0x%02"PRIx8" ", packet[n]);
//	}
	// SRC MAC (90:e2:ba:55:14:11)
	packet[0] = 0x90;
	packet[1] = 0xE2;
	packet[2] = 0xBA;
	packet[3] = 0x55;
	packet[4] = 0x14;
	packet[5] = 0x11;
	// DST MAC
	packet[6] = 0xFF;
	packet[7] = 0xFF;
	packet[8] = 0xFF;
	packet[9] = 0xFF;
	packet[10]= 0xFF;
	packet[11]= 0xFF;

	send_list[0] = false;
	send_list[1] = true;

	return packet_length;
}

#define DEVICES_MAX_COUNT 128u

// Packet processing
int main(int argc, char** argv)
{
	uint64_t devices_count = (uint64_t) argc - 1;
	struct tn_pci_device pci_devices[DEVICES_MAX_COUNT];
	if (devices_count == 0 || devices_count > DEVICES_MAX_COUNT || !tn_util_parse_pci(devices_count, argv+1, pci_devices)) {
		TN_INFO("Couldn't parse PCI devices from argv");
		return 1;
	}

	struct tn_net_pipe* pipe;
	if (!tn_net_pipe_init(&pipe)) {
		TN_INFO("Couldn't init pipe");
		return 2;
	}

	struct tn_net_device* devices[DEVICES_MAX_COUNT];
	for (uint8_t n = 0; n < devices_count; n++) {
		if (!tn_net_device_init(pci_devices[n], &(devices[n]))) {
			TN_INFO("Couldn't init device");
			return 3 + 100*n;
		}
		if (!tn_net_device_set_promiscuous(devices[n])) {
			TN_INFO("Couldn't make device promiscuous");
			return 4 + 100*n;
		}
	}

	if (!tn_net_pipe_set_receive(pipe, devices[0], 0)) {
		TN_INFO("Couldn't set pipe RX");
		return 5;
	}

	if (!tn_net_pipe_add_send(pipe, devices[0], 0)) {
		TN_INFO("Couldn't set pipe TX");
		return 6;
	}
	if (!tn_net_pipe_add_send(pipe, devices[1], 0)) {
		TN_INFO("Couldn't set pipe TX");
		return 7;
	}

	TN_INFO("Initialized successfully!");

	while(true) {
		tn_net_pipe_run_step(pipe, tinynf_packet_handler);
	}

//	TN_INFO("Done!");
//	return 0;
}
