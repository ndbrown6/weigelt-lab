include weigelt-lab/Makefile.inc

LOGDIR = log/sv_summary.$(NOW)

smry : $(foreach pair,$(SAMPLE_PAIRS),jasmine/$(pair)/$(pair)_mrg.vcf) \
       $(foreach pair,$(SAMPLE_PAIRS),jasmine/$(pair)/$(pair)_mrg_srt.vcf) \
       $(foreach pair,$(SAMPLE_PAIRS),jasmine/$(pair)/$(pair)_mrg_srt.txt)

REQUIRED_CALLERS ?= manta
OPTIONAL_CALLERS ?= svaba gridss
CALLERS ?= $(REQUIRED_CALLERS) $(OPTIONAL_CALLERS)
CALLER_MAKEFILES = manta:weigelt-lab/sv_callers/manta_tumor_normal.mk \
		   svaba:weigelt-lab/sv_callers/svaba_tumor_normal.mk \
		   gridss:weigelt-lab/sv_callers/gridss_tumor_normal.mk

get_makefile = $(patsubst $(1):%,%,$(filter $(1):%,$(CALLER_MAKEFILES)))
get_vcf_path = $(1)/$(2)_$(3)/$(2)_$(3).vcf
SORT_CMD = set -o pipefail && echo '##FILTER=<ID=PON,Description=\"Filtered by panel of normals\">' | bcftools annotate -h /dev/stdin $$(<) | bcftools sort -o $$(@)

PROJECT_DIR := $(notdir $(CURDIR))

JASMINE_CORES ?= 4
JASMINE_MEM_CORE ?= 8G

define jasmine-merge-sv
jasmine/$1_$2/$1_$2_mrg.vcf : $$(foreach caller,$$(CALLERS),$$(call get_vcf_path,$$(caller),$1,$2))
	$$(call RUN,-c -n $(JASMINE_CORES) -s 4G -m $(JASMINE_MEM_CORE) -p $(PROJECT_DIR)/jasmine -N $1_$2/merge -v $(JASMINE_ENV),"set -o pipefail && \
																    mkdir -p jasmine/$1_$2 && \
																    rm -f jasmine/$1_$2/vcf_list.txt && \
																    $$(foreach caller,$$(CALLERS),echo '$$(call get_vcf_path,$$(caller),$1,$2)' >> jasmine/$1_$2/vcf_list.txt &&) \
																    jasmine \
																    file_list=jasmine/$1_$2/vcf_list.txt \
																    out_file=jasmine/$1_$2/$1_$2_mrg.vcf \
																    genome_file=$$(REF_FASTA) \
																    --normalize_type \
																    --pre_normalize \
																    --ignore_strand \
																    --ignore_type \
																    max_dist=3000 \
																    min_seq_id=0.2 \
																    min_overlap=0.2 \
																    spec_reads=1 \
																    k_jaccard=5 \
																    threads=$(JASMINE_CORES)")
																			    
jasmine/$1_$2/$1_$2_mrg_srt.vcf : jasmine/$1_$2/$1_$2_mrg.vcf
	$$(call RUN,-c -n 1 -s 2G -m 4G -p $(PROJECT_DIR)/jasmine -N $1_$2/sort,"$(SORT_CMD)")
										 
jasmine/$1_$2/$1_$2_mrg_srt.txt : jasmine/$1_$2/$1_$2_mrg_srt.vcf
	$$(call RUN,-c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/jasmine -N $1/$2/annotate -v $(ANNOTATESV_ENV),"set -o pipefail && \
													  $$(ANNOTATE_SV) \
													  -SVinputFile $$(<) \
													  -outputFile $$(@) \
													  -genomeBuild GRCh37")

$$(foreach caller,$$(CALLERS), \
	$$(eval $$(call get_vcf_path,$$(caller),$1,$2) : ; $$(MAKE) -f $$(call get_makefile,$$(caller))))

endef
$(foreach pair,$(SAMPLE_PAIRS),\
	$(eval $(call jasmine-merge-sv,$(tumor.$(pair)),$(normal.$(pair)))))


..DUMMY := $(shell mkdir -p version; \
	$(JASMINE_ENV)/bin/jasmine --version &> version/sv_summary.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: smry clean

clean :
	rm jasmine/*/vcf_list.txt
