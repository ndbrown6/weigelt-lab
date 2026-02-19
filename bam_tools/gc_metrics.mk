include weigelt-lab/Makefile.inc

LOGDIR ?= log/gc_metrics.$(NOW)

metrics : $(foreach sample,$(SAMPLES),metrics/$(sample).gc_metrics_summary.txt) \
	  summary/gc_metrics.txt

TARGETS_LIST := $(TARGETS_FILE:.bed=.list)
BAITS_LIST := $(BAITS_FILE:.bed=.list)

PROJECT_DIR := $(notdir $(CURDIR))

define picard-metrics
metrics/$1.gc_metrics_summary.txt : bam/$1.bam
	$$(call RUN, -c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/metrics -N $1/gc_metrics,"set -o pipefail && \
										     $$(COLLECT_GC_BIAS) \
										     INPUT=$$(<) \
										     OUTPUT=metrics/$1.gc_metrics.txt \
										     CHART_OUTPUT=metrics/$1.gc_metrics.pdf \
										     REFERENCE_SEQUENCE=$$(REF_FASTA) \
										     SUMMARY_OUTPUT=$$(@)")

endef
$(foreach sample,$(SAMPLES),\
	$(eval $(call picard-metrics,$(sample))))
	
summary/gc_metrics.txt : $(foreach sample,$(SAMPLES),metrics/$(sample).gc_metrics_summary.txt)
	$(call RUN, -c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/summary -N summary/gc,"set -o pipefail && \
										 $(RSCRIPT) $(SCRIPTS_DIR)/summary/bam_metrics.R --option 5 --sample_names '$(SAMPLES)'")

..DUMMY := $(shell mkdir -p version; \
	echo "picard" >> version/gc_metrics.txt; \
	R --version >> version/gc_metrics.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: