#!/bin/bash
sudo asterisk -rx "pjsip show transport 0.0.0.0-udp"
sudo asterisk -rx "pjsip show endpoint sip-trunk"
