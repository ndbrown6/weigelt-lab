include weigelt-lab/Makefile.inc

LOGDIR = log/fusion_summary.$(NOW)

smry : summary/fusion_summary.txt

CALLERS ?= arriba starfusion
CALLER_MAKEFILES = arriba:weigelt-lab/fusion_callers/arriba_fusion.mk \
				   starfusion:weigelt-lab/fusion_callers/star_fusion.mk

get_makefile  = $(patsubst $(1):%,%,$(filter $(1):%,$(CALLER_MAKEFILES)))
get_smry_path = $(1)/fusion_summary.txt

PROJECT_DIR := $(notdir $(CURDIR))

$(foreach caller,$(CALLERS), \
	$(eval $(call get_smry_path,$(caller)) : ; $(MAKE) -f $(call get_makefile,$(caller)) smry_fusions))

summary/fusion_summary.txt : $(foreach caller,$(CALLERS),$(call get_smry_path,$(caller)))
	$(call RUN,-c -n 1 -s 8G -m 16G -v $(FUSIONSUMMARY_ENV) -p $(PROJECT_DIR)/summary -N merge_fusions,"set -o pipefail && \
																										mkdir -p summary && \
																										$(RSCRIPT) $(SCRIPTS_DIR)/summary/fusion_summary.R \
																										--arriba arriba/fusion_summary.txt \
																										--starfusion starfusion/fusion_summary.txt \
																										--ensembl $(HOME)/share/lib/resource_files/Hugo_ENST_ensembl75_fixed.txt \
																										--output $(@)")

..DUMMY := $(shell mkdir -p version; \
	$(ARRIBA_ENV)/bin/arriba -h &> version/fusion_summary.txt && \
	$(STARFUSION_ENV)/bin/STAR-Fusion --version &>> version/fusion_summary.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean :
	$(MAKE) -f $(call get_makefile,arriba) clean
	$(MAKE) -f $(call get_makefile,starfusion) clean
