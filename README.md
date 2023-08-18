# Configuration

1. Make sure you have the following dependencies installed:
   - Nextflow
   - Conda

2. Create a Conda environment using the provided YAML file:
   ```sh
   conda env create -f container/env.yml

# Running

The script called `run`:

```sh
  nextflow run com.nf \
	--fasta_info "61genus.info" \
	--reads "Steppe_bison.fastq.gz" \
	--fasta_index "~/extract_authentication/index/61genus" \
	--threads 10 \
	--label "61genus" \
	-with-trace
```

**Input**

`--fasta_info`: Specify the path to the fasta information file with the first column as the path to the fasta file and the second column as their name.

`--reads`: Provide the reads to be mapped.

`--fasta_index`: Set the directory containing the bowtie2 index of the concatenated fasta file of all fasta files.

`--threads`: Number of threads to use (e.g., 10 in the example).

`--label`: Label used for output.

`-with-trace`: Reports time and memory usage.

**Output**

All output are stored in a directory `Results/`

${label}_${reads_filename}.mapped_config_from

`${label}_${reads_filename}_reads_sum.csv` output 3 columns: 
- `species`: the name given to each fasta file in the input *.info file)	
- `n_reads_Sum`: the number of reads mapped to this fasta file

- `contigs_len_Sum`: the genome size summed from all contigs of the fasta file

**Subdirectory of Results/**

- `contigs`: contigs ID corresponding to the reference ID given in .info file.

- `mapping`: bam and their index, also extracted bam file with only reads mapped to each fasta file, which has a `-ext.bam` as suffix.

- `plot`: damage plots for authentication
