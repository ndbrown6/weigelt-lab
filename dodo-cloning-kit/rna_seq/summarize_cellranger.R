#!/usr/bin/env Rscript

suppressPackageStartupMessages(library("optparse"))
suppressPackageStartupMessages(library("Seurat"))
suppressPackageStartupMessages(library("Matrix"))
suppressPackageStartupMessages(library("hdf5r"))


if (!interactive()) {
    options(warn = -1, error = quote({ traceback(); q('no', status = 1) }))
}

optList <- list(make_option('--option', type = 'character', default = NA, help = ''),
				make_option('--sample_name', type = 'character', default = NA, help = ''),
	            make_option('--out_file', type = 'character', default = NA, help = ''))
parser <- OptionParser(usage = "%prog",  option_list=optList)
arguments <- parse_args(parser, positional_arguments = T)
opt <- arguments$options

if (as.numeric(opt$option)==2) {
	base_dir = paste0("cellranger/", as.character(opt$sample_name), "/outs/per_sample_outs/")
	out_file = as.character(opt$out_file)

	h5 = list.files(base_dir, pattern = "^sample_filtered_feature_bc_matrix\\.h5$", recursive = TRUE, full.names = TRUE)
	rel = sub(paste0("^", normalizePath(base_dir), "/?"), "", normalizePath(h5))
	samples = sub("/.*$", "", rel)
	names(h5) = samples

	objs <- lapply(samples, function(s) {
		m = Read10X_h5(h5[[s]])
		if (is.list(m)) {
			m = m[["Gene Expression"]]
		}
		o = CreateSeuratObject(counts = m, project = s, min.cells = 3, min.features = 0)
		o$sample = s
		o
	})
	names(objs) = samples

	if (length(objs) == 1) {
		tx = objs[[1]]
	} else {
		tx = merge(objs[[1]], y = objs[-1], add.cell.ids = samples, project = as.character(opt$sample_name))
	}

	if (as.numeric(substr(as.character(packageVersion("Seurat")), 1, 1)) >= 5) {
		tx = JoinLayers(tx)
	}

	tx[["percent.mt"]] = PercentageFeatureSet(tx, pattern = "^mt-")
	tx$group = NA_character_
	write.table(x = data.frame(cell = colnames(tx), tx@meta.data), file = sub("\\.rds$", ".txt", out_file), sep = "\t", row.names = FALSE)
	save(tx, file = out_file)
}
