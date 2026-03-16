ifneq ("$(wildcard config.inc)", "")
	include config.inc
endif
ifneq ("$(wildcard project_config.inc)", "")
	include project_config.inc
endif
include weigelt-lab/config/config.inc

export

NUM_ATTEMPTS ?= 10
NOW := $(shell date +"%F")
MAKELOG = log/$(@).$(NOW).log

USE_CLUSTER ?= true
QMAKE = weigelt-lab/dodo-cloning-kit/runtime/qmake.pl -n $@.$(NOW) $(if $(SLACK_CHANNEL),-c $(SLACK_CHANNEL)) -r $(NUM_ATTEMPTS) -m -s -- make
NUM_JOBS ?= 100

define RUN_QMAKE
$(QMAKE) -e -f $1 -j $2 $(TARGET) && \
	mkdir -p completed_tasks && \
	touch completed_tasks/$@
endef

RUN_MAKE = $(if $(findstring false,$(USE_CLUSTER))$(findstring n,$(MAKEFLAGS)),+$(MAKE) -f $1,$(call RUN_QMAKE,$1,$(NUM_JOBS)))

#==================================================
# Summary
#==================================================

TARGETS += mutation_summary
mutation_summary :
	$(call RUN_MAKE,weigelt-lab/summary/mutation_summary.mk) && \
	$(MAKE) -f weigelt-lab/summary/mutation_summary.mk clean
	
TARGETS += sv_summary
sv_summary :
	$(call RUN_MAKE,weigelt-lab/summary/sv_summary.mk) && \
	$(MAKE) -f weigelt-lab/summary/sv_summary.mk clean
	
TARGETS += fusion_summary
fusion_summary :
	$(call RUN_MAKE,weigelt-lab/summary/fusion_summary.mk) && \
	$(MAKE) -f weigelt-lab/summary/fusion_summary.mk clean	
	
#==================================================
# FASTQ aligners
#==================================================

TARGETS += align_impact_fastq
align_impact_fastq :
	$(call RUN_MAKE,weigelt-lab/fastq_aligners/align_impact_fastq.mk) && \
	$(MAKE) -f weigelt-lab/fastq_aligners/align_impact_fastq.mk clean
	
TARGETS += align_exome_fastq
align_exome_fastq :
	$(call RUN_MAKE,weigelt-lab/fastq_aligners/align_exome_fastq.mk) && \
	$(MAKE) -f weigelt-lab/fastq_aligners/align_exome_fastq.mk clean
	
TARGETS += align_genome_fastq
align_genome_fastq :
	$(call RUN_MAKE,weigelt-lab/fastq_aligners/align_genome_fastq.mk) && \
	$(MAKE) -f weigelt-lab/fastq_aligners/align_genome_fastq.mk clean
	
TARGETS += align_rnaseq_fastq
align_rnaseq_fastq :
	$(call RUN_MAKE,weigelt-lab/fastq_aligners/align_rnaseq_fastq.mk) && \
	$(MAKE) -f weigelt-lab/fastq_aligners/align_rnaseq_fastq.mk clean
	
#==================================================
# Variant callers
#==================================================

TARGETS += mutect_tumor_normal
mutect_tumor_normal :
	$(call RUN_MAKE,weigelt-lab/variant_callers/mutect_tumor_normal.mk) && \
	$(MAKE) -f weigelt-lab/variant_callers/mutect_tumor_normal.mk clean
	
TARGETS += varscan_tumor_normal
varscan_tumor_normal :
	$(call RUN_MAKE,weigelt-lab/variant_callers/varscan_tumor_normal.mk) && \
	$(MAKE) -f weigelt-lab/variant_callers/varscan_tumor_normal.mk clean
	
TARGETS += strelka_tumor_normal
strelka_tumor_normal :
	$(call RUN_MAKE,weigelt-lab/variant_callers/strelka_tumor_normal.mk) && \
	$(MAKE) -f weigelt-lab/variant_callers/strelka_tumor_normal.mk clean
	
TARGETS += scalpel_tumor_normal
scalpel_tumor_normal :
	$(call RUN_MAKE,weigelt-lab/variant_callers/scalpel_tumor_normal.mk) && \
	$(MAKE) -f weigelt-lab/variant_callers/scalpel_tumor_normal.mk clean
	
TARGETS += platypus_tumor_normal
platypus_tumor_normal :
	$(call RUN_MAKE,weigelt-lab/variant_callers/platypus_tumor_normal.mk) && \
	$(MAKE) -f weigelt-lab/variant_callers/platypus_tumor_normal.mk clean
	
#==================================================
# Copy number aberrations
#==================================================

TARGETS += facets_suite
facets_suite :
	$(call RUN_MAKE,weigelt-lab/copy_number/facets_suite.mk) && \
	$(MAKE) -f weigelt-lab/copy_number/facets_suite.mk clean

TARGETS += facets_refit
facets_refit :
	$(call RUN_MAKE,weigelt-lab/copy_number/facets_refit.mk) && \
	$(MAKE) -f weigelt-lab/copy_number/facets_refit.mk clean

TARGETS += cnv_kit
cnv_kit :
	$(call RUN_MAKE,weigelt-lab/copy_number/cnv_kit.mk) && \
	$(MAKE) -f weigelt-lab/copy_number/cnv_kit.mk clean
	
#==================================================
# RNA expression
#==================================================

TARGETS += kallisto_quant
kallisto_quant :
	$(call RUN_MAKE,weigelt-lab/rna_seq/kallisto_quant.mk) && \
	$(MAKE) -f weigelt-lab/rna_seq/kallisto_quant.mk clean
	
#==================================================
# DNA structural variant callers
#==================================================	

TARGETS += manta_tumor_normal
manta_tumor_normal :
	$(call RUN_MAKE,weigelt-lab/sv_callers/manta_tumor_normal.mk) && \
	$(MAKE) -f weigelt-lab/sv_callers/manta_tumor_normal.mk clean
	
TARGETS += svaba_tumor_normal
svaba_tumor_normal :
	$(call RUN_MAKE,weigelt-lab/sv_callers/svaba_tumor_normal.mk) && \
	$(MAKE) -f weigelt-lab/sv_callers/svaba_tumor_normal.mk clean
	
TARGETS += gridss_tumor_normal
gridss_tumor_normal :
	$(call RUN_MAKE,weigelt-lab/sv_callers/gridss_tumor_normal.mk) && \
	$(MAKE) -f weigelt-lab/sv_callers/gridss_tumor_normal.mk clean
	
TARGETS += delly_tumor_normal
delly_tumor_normal :
	$(call RUN_MAKE,weigelt-lab/sv_callers/delly_tumor_normal.mk) && \
	$(MAKE) -f weigelt-lab/sv_callers/delly_tumor_normal.mk clean
	
#==================================================
# RNA fusion callers
#==================================================

TARGETS += arriba_fusion
arriba_fusion :
	$(call RUN_MAKE,weigelt-lab/fusion_callers/arriba_fusion.mk) && \
	$(MAKE) -f weigelt-lab/fusion_callers/arriba_fusion.mk clean
	
TARGETS += star_fusion
star_fusion :
	$(call RUN_MAKE,weigelt-lab/fusion_callers/star_fusion.mk) && \
	$(MAKE) -f weigelt-lab/fusion_callers/star_fusion.mk clean

#==================================================
# VCF tools
#==================================================

TARGETS += annotate_vcf_maf
annotate_vcf_maf :
	$(call RUN_MAKE,weigelt-lab/vcf_tools/annotate_vcf_maf.mk)
	
TARGETS += annotate_maf_vcf
annotate_maf_vcf :
	$(call RUN_MAKE,weigelt-lab/vcf_tools/annotate_maf_vcf.mk)
	
#==================================================
# BAM tools
#==================================================

TARGETS += idx_metrics
idx_metrics :
	$(call RUN_MAKE,weigelt-lab/bam_tools/idx_metrics.mk)

TARGETS += aln_metrics
aln_metrics :
	$(call RUN_MAKE,weigelt-lab/bam_tools/aln_metrics.mk)

TARGETS += insert_metrics
insert_metrics :
	$(call RUN_MAKE,weigelt-lab/bam_tools/insert_metrics.mk)

TARGETS += oxog_metrics
oxog_metrics :
	$(call RUN_MAKE,weigelt-lab/bam_tools/oxog_metrics.mk)

TARGETS += gc_metrics
gc_metrics :
	$(call RUN_MAKE,weigelt-lab/bam_tools/gc_metrics.mk)

TARGETS += hs_metrics
hs_metrics :
	$(call RUN_MAKE,weigelt-lab/bam_tools/hs_metrics.mk)

TARGETS += dup_metrics
dup_metrics :
	$(call RUN_MAKE,weigelt-lab/bam_tools/dup_metrics.mk)
	
TARGETS += wgs_metrics
wgs_metrics :
	$(call RUN_MAKE,weigelt-lab/bam_tools/wgs_metrics.mk)
	
TARGETS += rnaseq_metrics
rnaseq_metrics :
	$(call RUN_MAKE,weigelt-lab/bam_tools/rnaseq_metrics.mk)

#==================================================
# Beta test
#==================================================

TARGETS += hla_polysolver
hla_polysolver :
	$(call RUN_MAKE,weigelt-lab/misc/hla_polysolver.mk) && \
	$(MAKE) -f weigelt-lab/misc/hla_polysolver.mk clean
	
TARGETS += immune_deconvolution
immune_deconvolution :
	$(call RUN_MAKE,weigelt-lab/misc/immune_deconvolution.mk) && \
	$(MAKE) -f weigelt-lab/misc/immune_deconvolution.mk clean	
	
TARGETS += msi_sensor
msi_sensor :
	$(call RUN_MAKE,weigelt-lab/misc/msi_sensor.mk) && \
	$(MAKE) -f weigelt-lab/misc/msi_sensor.mk clean

TARGETS += mi_msi
mi_msi :
	$(call RUN_MAKE,weigelt-lab/misc/mi_msi.mk) && \
	$(MAKE) -f weigelt-lab/misc/mi_msi.mk clean

TARGETS += hr_detect
hr_detect :
	$(call RUN_MAKE,weigelt-lab/misc/hr_detect.mk) && \
	$(MAKE) -f weigelt-lab/misc/hr_detect.mk clean
	
TARGETS += cn_hrd
cn_hrd :
	$(call RUN_MAKE,weigelt-lab/misc/cn_hrd.mk) && \
	$(MAKE) -f weigelt-lab/misc/cn_hrd.mk clean	

TARGETS += deconstruct_sigs
deconstruct_sigs :
	$(call RUN_MAKE,weigelt-lab/misc/deconstruct_sigs.mk) && \
	$(MAKE) -f weigelt-lab/misc/deconstruct_sigs.mk clean
	
TARGETS += sv_signtaure
sv_signtaure :
	$(call RUN_MAKE,weigelt-lab/misc/sv_signtaure.mk) && \
	$(MAKE) -f weigelt-lab/misc/sv_signtaure.mk clean

TARGETS += star_fish
star_fish :
	$(call RUN_MAKE,weigelt-lab/misc/star_fish.mk) && \
	$(MAKE) -f weigelt-lab/misc/star_fish.mk clean
	
TARGETS += sufam_genotype
sufam_genotype :
	$(call RUN_MAKE,weigelt-lab/misc/sufam_genotype.mk) && \
	$(MAKE) -f weigelt-lab/misc/sufam_genotype.mk clean
	
TARGETS += pyclone_vi
pyclone_vi :
	$(call RUN_MAKE,weigelt-lab/misc/pyclone_vi.mk) && \
	$(MAKE) -f weigelt-lab/misc/pyclone_vi.mk clean
	
TARGETS += medicc2_cn
medicc2_cn :
	$(call RUN_MAKE,weigelt-lab/misc/medicc2_cn.mk) && \
	$(MAKE) -f weigelt-lab/misc/medicc2_cn.mk clean
	
TARGETS += cluster_samples
cluster_samples :
	$(call RUN_MAKE,weigelt-lab/misc/cluster_samples.mk) && \
	$(MAKE) -f weigelt-lab/misc/cluster_samples.mk clean
	
.PHONY : $(TARGETS)
