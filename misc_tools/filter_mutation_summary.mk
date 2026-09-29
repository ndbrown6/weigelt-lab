include weigelt-lab/Makefile.inc

LOGDIR ?= log/filter_mutation_summary.$(NOW)

smry : summary/mutation_summary_ft.txt

PROJECT_DIR := $(notdir $(CURDIR))

ifneq ($(findstring IMPACT,$(TARGETS_FILE)),)
FILTER = weigelt-lab/rda_cache/rpart.im.obj
else
FILTER = weigelt-lab/rda_cache/rpart.im.obj
endif

summary/mutation_summary_ft.txt : summary/mutation_summary.txt
	$(call RUN,-c -n 1 -s 12G -m 24G -p $(PROJECT_DIR)/summary -N filter-smry -v $(RPART_ENV),"set -o pipefail && \
																							   mkdir -p summary && \
																							   $(RSCRIPT) $(SCRIPTS_DIR)/summary/filter_mutation_summary.R \
																							   --filter $(FILTER) \
																							   --input $(<) \
																							   --output $(@)")

..DUMMY := $(shell mkdir -p version; \
	R --version >> version/filter_mutation_summary.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: smry
