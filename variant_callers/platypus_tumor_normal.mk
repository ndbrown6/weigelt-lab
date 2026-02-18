include weigelt-lab/Makefile.inc

LOGDIR ?= log/platypus_tumor_normal.$(NOW)

PLATYPUS_CHUNKS := $(shell seq 1 22) X Y

vcf: $(foreach pair,$(SAMPLE_PAIRS),$(foreach n,$(PLATYPUS_CHUNKS),platypus/$(pair)/$(pair)--$(n).vcf))

define platypus-tumor-normal-chunk
platypus/$1_$2/$1_$2--$3.vcf : bam/$1.bam bam/$2.bam
	$$(call RUN,-c -n 4 -s 2G -m 3G -v $(PLATYPUS_ENV) -p $(PROJECT_DIR)/platypus -N $1/$3,"set -o pipefail && \
												platypus callVariants \
												--refFile=$$(REF_FASTA) \
												--regions=$3 \
												--bamFiles=$$(<)$$(,)$$(<<) \
												--logFileName=platypus/$1_$2/$1_$2--$3.log \
												--nCPU=4 \
												--skipDifficultWindows=1 \
												--genSNPs=FALSE \
												--genIndels=TRUE \
												--mergeClusteredVariants=1 \
												--trimOverlapping=1 \
												--trimAdapter=1 \
												--trimSoftClipped=1 \
												--output=$$(@)")

endef
$(foreach pair,$(SAMPLE_PAIRS), \
	$(foreach n,$(PLATYPUS_CHUNKS), \
			$(eval $(call platypus-tumor-normal-chunk,$(tumor.$(pair)),$(normal.$(pair)),$(n)))))

..DUMMY := $(shell mkdir -p version)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean :
	rm -f scalpel/chunk_bed/* && \
	rm -rf scalpel/*/*/