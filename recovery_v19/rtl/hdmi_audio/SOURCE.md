HDMI packet modules: https://github.com/hdl-util/hdmi
MIT OR Apache-2.0; original attribution and license files included.
Commit: 83b1c9543a91b776671a44e68e130f81cae437b7
Local changes: clock enables for shared 125MHz clock; deterministic zero unused fields. Packet scheduling, video symbol mux and 48kHz tone integration are in hdmi_audio_bridge.sv.
