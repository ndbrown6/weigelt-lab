include weigelt-lab/Makefile.inc

LOGDIR ?= log/mutation_summary.$(NOW)

PROJECT_DIR := $(notdir $(CURDIR))
CALLERS = mutect strelka varscan scalpel platypus
CALLER_MAKEFILES = mutect:weigelt-lab/variant_caller/mutect_tumor_normal.mk \
		   strelka:weigelt-lab/variant_caller/strelka_tumor_normal.mk \
		   varscan:weigelt-lab/variant_caller/varscan_tumor_normal.mk \
		   scalpel:weigelt-lab/variant_caller/scalpel_tumor_normal.mk \
		   platypus:weigelt-lab/variant_caller/platypus_tumor_normal.mk

get_makefile = $(patsubst $(1):%,%,$(filter $(1):%,$(CALLER_MAKEFILES)))

smry : summary/mutation_summary.maf

define caller-rule
$(1)/mutation_summary.maf :
	$$(MAKE) -f $$(call get_makefile,$(1)) $(1)/mutation_summary.maf

endef
$(foreach caller,$(CALLERS), \
	$(eval $(call caller-rule,$(caller))))

define maf-args
$(foreach caller,$(CALLERS),--$(caller)_maf $(caller)/mutation_summary.maf)
endef

summary/mutation_summary.maf : $(foreach caller,$(CALLERS),$(caller)/mutation_summary.maf)
	$(call RUN,-c -n 1 -s 12G -m 24G -p $(PROJECT_DIR)/summary -N combine-maf,"set -o pipefail && \
										   mkdir -p summary && \
										   $(RSCRIPT) $(SCRIPTS_DIR)/combine_caller_mafs.R \
										   $(maf-args) \
										   --output summary/mutation_summary.maf")

.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: smry
