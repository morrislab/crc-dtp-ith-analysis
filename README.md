Description
===========
This repository contains Pairtree input files and analysis script for
"Colorectal cancer cells possess an equipotent capacity to enter a reversible
diapause-like state to survive chemotherapy" with Sumaiyah Rehman, ...,
Catherine O'Brien.

Jeff Wintersinger performed this analysis.

Inputs
======
inputs.nocna.separated: input files split into separate samples, containing
only mutations from diploid regions for each sample individually

inputs.nocna.combined: input files split into separate samples, containing only
mutations from the intersection of diploid regions across samples. Mutations
absent from a sample are given zero variant reads, and a total number of reads
corresponding to however many reads were present at that genomic locus.
