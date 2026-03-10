include innovation-lab/Makefile.inc

LOGDIR ?= log/fusion_catcher.$(NOW)

fusion_catcher : $(foreach sample,$(SAMPLES),fusioncatcher/$(sample)/$(sample).1.fastq.gz) \
		 $(foreach sample,$(SAMPLES),fusioncatcher/$(sample)/$(sample).2.fastq.gz) \
		 $(foreach sample,$(SAMPLES),fusioncatcher/$(sample)/out/taskcomplete) \
		 fusioncatcher/summary.txt
				 
CACHE = $(HOME)/share/usr/env/fusioncatcher-1.2.0/share/fusioncatcher-1.20/db/current

define merged-fastq
fusioncatcher/$1/$1.1.fastq.gz : $$(foreach split,$2,$$(word 1, $$(fq.$$(split))))
	$$(call RUN,-c -n 12 -s 0.5G -m 1G -v $(PIGZ_ENV),"set -o pipefail && \
							$$(PIGZ) -cd -p 12 $$(^) | $$(PIGZ) -c -p 12 > $$(@)")
					 
fusioncatcher/$1/$1.2.fastq.gz : $$(foreach split,$2,$$(word 2, $$(fq.$$(split))))
	$$(call RUN,-c -n 12 -s 0.5G -m 1G -v $(PIGZ_ENV),"set -o pipefail && \
							$$(PIGZ) -cd -p 12 $$(^) | $$(PIGZ) -c -p 12 > $$(@)")

endef
$(foreach sample,$(SAMPLES),\
		$(eval $(call merged-fastq,$(sample),$(split.$(sample)))))

define fusion-catcher
fusioncatcher/$1/out/taskcomplete : fusioncatcher/$1/$1.1.fastq.gz fusioncatcher/$1/$1.2.fastq.gz
	$$(call RUN,-c -n 8 -s 4G -m 6G -v $(FUSIONCATCHER_ENV) -w 72:00:00,"set -o pipefail && \
									     mkdir -p fusioncatcher/$1/out && \
									     fusioncatcher.py \
									     -i fusioncatcher/$1 \
									     -o fusioncatcher/$1/out \
									     -d $$(CACHE) \
									     -p 8 && \
									     echo $1 > fusioncatcher/$1/out/taskcomplete")

endef
$(foreach sample,$(SAMPLES),\
		$(eval $(call fusion-catcher,$(sample))))
		
fusioncatcher/summary.txt : $(foreach sample,$(SAMPLES),fusioncatcher/$(sample)/out/taskcomplete)
	echo "Gene_1_symbol(5end_fusion_partner)	Gene_2_symbol(3end_fusion_partner)	Fusion_description	Counts_of_common_mapping_reads	Spanning_pairs	Spanning_unique_reads	Longest_anchor_found	Fusion_finding_method	Fusion_point_for_gene_1(5end_fusion_partner)	Fusion_point_for_gene_2(3end_fusion_partner)	Gene_1_id(5end_fusion_partner)	Gene_2_id(3end_fusion_partner)	Exon_1_id(5end_fusion_partner)	Exon_2_id(3end_fusion_partner)	Fusion_sequence	Predicted_effect	Sample_name" > fusioncatcher/summary.txt; \
	for i in $(SAMPLES); do \
		sed -e "1d" fusioncatcher/$$i/out/final-list_candidate-fusion-genes.hg19.txt | sed "s/$$/\t$$i/" >> fusioncatcher/summary.txt; \
	done

..DUMMY := $(shell mkdir -p version; \
	     ~/share/usr/env/fusioncatcher-1.2.0/bin/fusioncatcher.py --version &> version/fusioncatcher.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: fusion_catcher
