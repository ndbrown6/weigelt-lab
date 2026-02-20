include weigelt-lab/Makefile.inc

LOGDIR ?= log/insert_metrics.$(NOW)

metrics : $(foreach sample,$(SAMPLES),metrics/$(sample).insert_metrics.txt) \
	  summary/insert_metrics.txt
	 
TARGETS_LIST := $(TARGETS_FILE:.bed=.list)
BAITS_LIST := $(BAITS_FILE:.bed=.list)

PROJECT_DIR := $(notdir $(CURDIR))

define picard-metrics
metrics/$1.insert_metrics.txt : bam/$1.bam
	$$(call RUN, -c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/metrics -N $1/insert_metrics,"set -o pipefail && \
											 $$(COLLECT_INSERT_METRICS) \
											 INPUT=$$(<) \
											 OUTPUT=$$(@) \
											 HISTOGRAM_FILE=metrics/$1.insert_metrics.pdf \
											 MINIMUM_PCT=0.05")
									   
endef
$(foreach sample,$(SAMPLES),\
	$(eval $(call picard-metrics,$(sample))))
	
summary/insert_metrics.txt : $(foreach sample,$(SAMPLES),metrics/$(sample).insert_metrics.txt)
	$(call RUN, -c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/summary -N metrics/insert,"set -o pipefail && \
										     $(RSCRIPT) $(SCRIPTS_DIR)/summary/bam_metrics.R --option 3 --sample_names '$(SAMPLES)'")

..DUMMY := $(shell mkdir -p version; \
	echo "picard" >> version/insert_metrics.txt; \
	R --version >> version/insert_metrics.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: metrics