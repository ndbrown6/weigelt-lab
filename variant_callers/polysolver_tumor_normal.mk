include weigelt-lab/Makefile.inc

LOGDIR ?= log/polysolver_tumor_normal.$(NOW)


polysolver : $(foreach pair,$(SAMPLE_PAIRS),hla_polysolver/$(pair)/winners.hla.txt) \
			 $(foreach pair,$(SAMPLE_PAIRS),hla_polysolver/$(pair)/hla.intervals) \
			 $(foreach pair,$(SAMPLE_PAIRS),hla_polysolver/$(pair)/$(pair).mutect.unfiltered.annotated) \
			 $(foreach pair,$(SAMPLE_PAIRS),hla_polysolver/$(pair)/$(pair).strelka_indels.unfiltered.annotated) \
			 hla_polysolver/summary/hla_summary.txt \
			 hla_polysolver/summary/mutect_summary.txt \
			 hla_polysolver/summary/strelka_summary.txt

PROJECT_DIR := $(notdir $(CURDIR))

define hla-polysolver
hla_polysolver/$1_$2/winners.hla.txt : bam/$1.bam bam/$2.bam
	$$(call RUN,-c -n 8 -s 2G -m 4G -v $(POLYSOLVER_ENV) -p $(PROJECT_DIR)/hla_type -N $1/$2 -w 72:00:00, "set -o pipefail && \
																										   shell_call_hla_type \
																										   $$(<<) \
																										   Unknown \
																										   1 \
																										   hg19 \
																										   STDFQ \
																										   0 \
																										   hla_polysolver/$1_$2")

hla_polysolver/$1_$2/hla.intervals : bam/$1.bam bam/$2.bam hla_polysolver/$1_$2/winners.hla.txt
	$$(call RUN,-c -n 8 -s 2G -m 4G -v $(POLYSOLVER_ENV) -p $(PROJECT_DIR)/hla_mutations -N $1/$2 -w 72:00:00, "set -o pipefail && \
																											    shell_call_hla_mutations_from_type \
																											    $$(<<) \
																											    $$(<) \
																											    $$(<<<) \
																											    hg19 \
																											    STDFQ \
																											    hla_polysolver/$1_$2")

hla_polysolver/$1_$2/$1_$2.mutect.unfiltered.annotated : hla_polysolver/$1_$2/hla.intervals
	$$(call RUN,-c -n 8 -s 2G -m 4G -v $(POLYSOLVER_ENV) -p $(PROJECT_DIR)/annotate -N $1/$2 -w 72:00:00, "set -o pipefail && \
																										   shell_annotate_hla_mutations \
																										   $1_$2 \
																										   hla_polysolver/$1_$2")

hla_polysolver/$1_$2/$1_$2.strelka_indels.unfiltered.annotated : hla_polysolver/$1_$2/$1_$2.mutect.unfiltered.annotated

endef
$(foreach pair,$(SAMPLE_PAIRS),\
	$(eval $(call hla-polysolver,$(tumor.$(pair)),$(normal.$(pair)))))

hla_polysolver/summary/hla_summary.txt : $(foreach pair,$(SAMPLE_PAIRS),hla_polysolver/$(pair)/$(pair).mutect.unfiltered.annotated) $(foreach pair,$(SAMPLE_PAIRS),hla_polysolver/$(pair)/$(pair).strelka_indels.unfiltered.annotated)
	$(call RUN,-c -s 12G -m 24G -p $(PROJECT_DIR)/summary -N hla_summary,"set -o pipefail && \
																		  mkdir -p hla_polysolver/summary && \
																		  $(RSCRIPT) $(SCRIPTS_DIR)variant_callers/polysolver.R \
																		  --option 1 \
																		  --sample_names '$(SAMPLE_PAIRS)'")

hla_polysolver/summary/mutect_summary.txt : $(foreach pair,$(SAMPLE_PAIRS),hla_polysolver/$(pair)/$(pair).mutect.unfiltered.annotated) $(foreach pair,$(SAMPLE_PAIRS),hla_polysolver/$(pair)/$(pair).strelka_indels.unfiltered.annotated)
	$(call RUN,-c -s 12G -m 24G -p $(PROJECT_DIR)/summary -N mutect_summary,"set -o pipefail && \
																			 mkdir -p hla_polysolver/summary && \
																			 $(RSCRIPT) $(SCRIPTS_DIR)/variant_callers/polysolver.R \
																			 --option 2 \
																			 --sample_names '$(SAMPLE_PAIRS)'")

hla_polysolver/summary/strelka_summary.txt : $(foreach pair,$(SAMPLE_PAIRS),hla_polysolver/$(pair)/$(pair).mutect.unfiltered.annotated) $(foreach pair,$(SAMPLE_PAIRS),hla_polysolver/$(pair)/$(pair).strelka_indels.unfiltered.annotated)
	$(call RUN,-c -s 12G -m 24G -p $(PROJECT_DIR)/summary -N strelka_summary,"set -o pipefail && \
																			  mkdir -p hla_polysolver/summary && \
																			  $(RSCRIPT) $(SCRIPTS_DIR)/variant_callers/polysolver.R \
																			  --option 3 \
																			  --sample_names '$(SAMPLE_PAIRS)'")

..DUMMY := $(shell mkdir -p version; \
	$(POLYSOLVER_ENV)/bin/shell_call_hla_type --help &> version/polysolver_tumor_normal.txt; \
	$(POLYSOLVER_ENV)/bin/shell_call_hla_mutations_from_type --help &>> version/polysolver_tumor_normal.txt; \
	$(POLYSOLVER_ENV)/bin/shell_annotate_hla_mutations --help &>> version/polysolver_tumor_normal.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean :
	rm -f hla_polysolver/*/*.out && \
	rm -f hla_polysolver/*/*.vcf && \
	rm -f hla_polysolver/*/ids_*
