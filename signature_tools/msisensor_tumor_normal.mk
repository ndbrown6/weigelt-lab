include weigelt-lab/Makefile.inc

LOGDIR ?= log/msisensor_tumor_normal.$(NOW)

smry : $(foreach pair,$(SAMPLE_PAIRS),msisensor/$(pair)/$(pair).msi) \
	   msisensor/msi_summary.txt
	   
PROJECT_DIR := $(notdir $(CURDIR))

MICROSATELLITES_LIST = $(HOME)/share/lib/resource_files/MSIsensor/microsatellites.list
MSI_REGIONS = $(HOME)/share/lib/resource_files/MSIsensor/msiregions.bed

BAM_SOURCE ?= local

ifeq ($(BAM_SOURCE),irb)
define msisensor-tumor-normal
msisensor/$1_$2/$1_$2.msi :
	$$(call RUN,-c -n 8 -s 1G -m 2G -v $(MSISENSOR_ENV) -p $(PROJECT_DIR)/msisensor -N $1/$2,"set -o pipefail && \
																							  mkdir -p msisensor/$1_$2/ && \
																							  msisensor msi $$(MSISENSOR_OPTS) \
																							  -d $$(MICROSATELLITES_LIST) \
																							  -e $$(MSI_REGIONS) \
																							  -n /data1/share001/share/impact_12_245/`echo $2 | cut -c 1-1`/`echo $2 | cut -c 2-2`/$2.bam \
																							  -t /data1/share001/share/impact_12_245/`echo $1 | cut -c 1-1`/`echo $1 | cut -c 2-2`/$1.bam \
																							  -b 8 \
																							  -o $$(@)")
endef
$(foreach pair,$(SAMPLE_PAIRS),\
	$(eval $(call msisensor-tumor-normal,$(tumor.$(pair)),$(normal.$(pair)))))
else
define msisensor-tumor-normal
msisensor/$1_$2/$1_$2.msi : bam/$1.bam bam/$2.bam
	$$(call RUN,-c -n 8 -s 1G -m 2G -v $(MSISENSOR_ENV) -p $(PROJECT_DIR)/msisensor -N $1/$2,"set -o pipefail && \
																							  mkdir -p msisensor/$1_$2/ && \
																							  msisensor msi $$(MSISENSOR_OPTS) \
																							  -d $$(MICROSATELLITES_LIST) \
																							  -e $$(MSI_REGIONS) \
																							  -n $$(<<) \
																							  -t $$(<) \
																							  -b 8 \
																							  -o $$(@)")
endef
$(foreach pair,$(SAMPLE_PAIRS),\
	$(eval $(call msisensor-tumor-normal,$(tumor.$(pair)),$(normal.$(pair)))))
endif

msisensor/msi_summary.txt : $(foreach pair,$(SAMPLE_PAIRS),msisensor/$(pair)/$(pair).msi)
	$(INIT) (head -1 $< | sed 's/^/sample\t/'; for x in $^; do sed "1d; s/^/$$(basename $$x)\t/" $$x; done | sed 's/_.*msi//' ) > $@

..DUMMY := $(shell mkdir -p version; \
	$(MSISENSOR_ENV)/bin/msisensor &> version/msisensor_tumor_normal.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean :
