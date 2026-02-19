include weigelt-lab/Makefile.inc

LOGDIR ?= log/mutation_summary.$(NOW)

smry : summary/mutation_summary.maf

REQUIRED_CALLERS = mutect
OPTIONAL_CALLERS = strelka varscan scalpel platypus
CALLERS = $(REQUIRED_CALLERS) $(OPTIONAL_CALLERS)
CALLER_MAKEFILES = mutect:weigelt-lab/variant_callers/mutect_tumor_normal.mk \
		   strelka:weigelt-lab/variant_callers/strelka_tumor_normal.mk \
		   varscan:weigelt-lab/variant_callers/varscan_tumor_normal.mk \
		   scalpel:weigelt-lab/variant_callers/scalpel_tumor_normal.mk \
		   platypus:weigelt-lab/variant_callers/platypus_tumor_normal.mk

get_makefile = $(patsubst $(1):%,%,$(filter $(1):%,$(CALLER_MAKEFILES)))

PROJECT_DIR := $(notdir $(CURDIR))

define caller-rule
$(1)/mutation_summary.maf :
	$$(MAKE) -f $$(call get_makefile,$(1)) $$(@)

endef
$(foreach caller,$(CALLERS), \
	$(eval $(call caller-rule,$(caller))))

facets_suite/summary/aggregated-gene.txt :
	$(MAKE) -f weigelt-lab/copy_number/facets_suite.mk facets

define maf-args
$(foreach caller,$(CALLERS),--$(caller)_maf $(caller)/mutation_summary.maf)
endef

summary/mutation_summary.maf : $(foreach caller,$(CALLERS),$(caller)/mutation_summary.maf) facets_suite/summary/aggregated-gene.txt
	$(call RUN,-c -n 1 -s 12G -m 24G -p $(PROJECT_DIR)/summary -N combine-maf,"set -o pipefail && \
										   mkdir -p summary && \
										   $(RSCRIPT) $(SCRIPTS_DIR)/summary/mutation_summary.R \
										   $(maf-args) \
										   --facets_gene facets_suite/summary/aggregated-gene.txt \
										   --output $(@)")

..DUMMY := $(shell mkdir -p version; \
	R --version >> version/mutation_summary.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: smry clean

clean:
    @echo "Cleaning mutation callers..." && \
    $(foreach caller,$(CALLERS),$(MAKE) -f $(call get_makefile,$(caller)) clean;) && \
    @echo "Cleaning facets suite..." && \
    $(MAKE) -f weigelt-lab/copy_number/facets_suite.mk clean
