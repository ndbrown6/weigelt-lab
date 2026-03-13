#!/usr/bin/env Rscript

suppressPackageStartupMessages(library("optparse"))
suppressPackageStartupMessages(library("readr"))
suppressPackageStartupMessages(library("dplyr"))
suppressPackageStartupMessages(library("magrittr"))

if (!interactive()) {
    options(warn = -1, error = quote({ traceback(); q('no', status = 1) }))
}

optList = list(make_option('--option', type = 'character', default = NA, help = 'analysis type'),
			   make_option('--sample_names', type = 'character', default = NA, help = 'list of samples names'),
			   make_option('--ensembl', type = 'character', default = NA, help = 'Ensembl database'))
parser = OptionParser(usage = "%prog",  option_list=optList)
arguments = parse_args(parser, positional_arguments = T)
opt = arguments$options

if (as.numeric(opt$option) == 1) {

	sample_name = unlist(strsplit(x=opt$sample_names, split=" ", fixed=TRUE))
	fusions = readr::read_tsv(file = paste0("starfusion/", sample_name, "/fusions.tsv"), col_names = TRUE, col_types = cols(.default = col_character())) %>%
			  readr::type_convert() %>%
			  dplyr::mutate(`#gene1`= unlist(lapply(`#FusionName`, function(x) { (strsplit(x, split = "--")[[1]])[1] })),
							gene2 = unlist(lapply(`#FusionName`, function(x) { (strsplit(x, split = "--")[[1]])[2] })),
							`strand1(gene/fusion)` = "+/+",
							`strand2(gene/fusion)` = "+/+",
							breakpoint1 = unlist(lapply(LeftBreakpoint, function(x) { paste0((strsplit(x, split = ":")[[1]])[1:2], collapse = ":") })),
							breakpoint2 = unlist(lapply(RightBreakpoint, function(x) { paste0((strsplit(x, split = ":")[[1]])[1:2], collapse = ":") })),
							site1 = "CDS/splice-site",
							site2 = "CDS/splice-site",
							type = "translocation",
							split_reads1 = JunctionReadCount,
							split_reads2 = JunctionReadCount,
							discordant_mates = SpanningFragCount,
							coverage1 = JunctionReadCount + SpanningFragCount,
							coverage2 = JunctionReadCount + SpanningFragCount,
							confidence = "high",
							reading_frame = ".",
							tags = ".",
							retained_protein_domains = ".",
							closest_genomic_breakpoint1 = ".",
							closest_genomic_breakpoint2 = ".",
							gene_id1 = unlist(lapply(LeftGene, function(x) { unlist(strsplit(x, '^', fixed = TRUE, perl = FALSE))[2] })),
							gene_id2 = unlist(lapply(RightGene, function(x) { unlist(strsplit(x, '^', fixed = TRUE, perl = FALSE))[2] })),
							transcript_id1 = ".",
							transcript_id2 = ".",
							direction1 = "downstream",
							direction2 = "upstream",
							filters = ".",
							fusion_transcript = ".",
							peptide_sequence = ".",
							read_identifiers = ".") %>%
							dplyr::mutate(gene_id1 = unlist(lapply(gene_id1, function(x) { unlist(strsplit(x, '.', fixed = TRUE, perl = FALSE))[1] })),
										  gene_id2 = unlist(lapply(gene_id2, function(x) { unlist(strsplit(x, '.', fixed = TRUE, perl = FALSE))[1] }))) %>%
							dplyr::select(16:45)
							
	Hugo_ENST_ensembl = readr::read_tsv(file = as.character(opt$ensembl), col_names = TRUE, col_types = cols(.default = col_character())) %>%
						readr::type_convert()
						
	for (i in 1:nrow(fusions)) {
		fusions$transcript_id1[i] = Hugo_ENST_ensembl %>%
									dplyr::filter(ensg == fusions$gene_id1[i]) %>%
									dplyr::slice(1) %>%
									.[["target_id"]]
		fusions$transcript_id2[i] = Hugo_ENST_ensembl %>%
									dplyr::filter(ensg == fusions$gene_id2[i]) %>%
									dplyr::slice(1) %>%
									.[["target_id"]]
	}
							
	readr::write_tsv(x = fusions, path = paste0("starfusion/", sample_name, "/fusions.txt"), append=FALSE, col_names=TRUE, quote_escape=FALSE)

} else if (as.numeric(opt$option) == 2) {
	
	sample_names = unlist(strsplit(x=opt$sample_names, split=" ", fixed=TRUE))
	smry = list()
	for (i in 1:length(sample_names)) {
		smry[[i]] = readr::read_tsv(file=paste0("starfusion/", sample_names[i], "/fusions.tsv"), col_names = TRUE, col_types = cols(.default = col_character())) %>%
				    dplyr::mutate(sample_name = sample_names[i])
	}
	smry = do.call(rbind, smry)
	readr::write_tsv(x=smry, path="starfusion/fusion_summary.txt", append=FALSE, col_names=TRUE, quote_escape=FALSE)

}
