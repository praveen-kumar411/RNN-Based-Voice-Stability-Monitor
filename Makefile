# cocotb 2.x Makefile for rnn_vsm_top
SIM ?= xcelium
TOPLEVEL_LANG = verilog

VERILOG_SOURCES = $(PWD)/mem_rw.v $(PWD)/hstate_rf.v $(PWD)/requant.v \
                  $(PWD)/act_lut_syn.v $(PWD)/gru_core.v $(PWD)/ema.v \
                  $(PWD)/alert.v $(PWD)/regs.v $(PWD)/axis_feat_buf.v \
                  $(PWD)/icg.v $(PWD)/rnn_vsm_top.v

COCOTB_TOPLEVEL     = rnn_vsm_top
COCOTB_TEST_MODULES = test_rnn_vsm

export PYTHONPATH := $(PWD):$(PYTHONPATH)

include $(shell cocotb-config --makefiles)/Makefile.sim
