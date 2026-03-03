#!/usr/bin/env Rscript

suppressPackageStartupMessages(library("optparse"))
suppressPackageStartupMessages(library("readr"))
suppressPackageStartupMessages(library("dplyr"))
suppressPackageStartupMessages(library("magrittr"))

if (!interactive()) {
    options(warn = -1, error = quote({ traceback(); q('no', status = 1) }))
}

optList = list(make_option('--sample_names', type = 'character', default = NA, help = 'list of samples names'))
parser = OptionParser(usage = "%prog",  option_list=optList)
arguments = parse_args(parser, positional_arguments = T)
opt = arguments$options

sample_names = unlist(strsplit(x=opt$sample_names, split=" ", fixed=TRUE))
smry = list()
for (i in 1:length(sample_names)) {
	smry[[i]] = readr::read_tsv(file=paste0("arriba/", sample_names[i], "/fusions.tsv"), col_names = TRUE, col_types = cols(.default = col_character())) %>%
		    dplyr::mutate(sample_name = sample_names[i])
}
smry = do.call(rbind, smry)
readr::write_tsv(x=smry, path="arriba/fusion_summary.txt", append=FALSE, col_names=TRUE, quote_escape=FALSE)
