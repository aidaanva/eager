//
// Complexity filtering and metagenomics screening of sequencing reads
//

// Much taken from nf-core/taxprofile subworkflows/local/profiling.nf

include { MALT_RUN                       } from '../../modules/nf-core/malt/run/main'
include { KRAKEN2_KRAKEN2                } from '../../modules/nf-core/kraken2/kraken2/main'
include { KRAKENUNIQ_PRELOADEDKRAKENUNIQ } from '../../modules/nf-core/krakenuniq/preloadedkrakenuniq/main'
include { METAPHLAN_METAPHLAN            } from '../../modules/nf-core/metaphlan/metaphlan/main'
include { CAT_CAT as CAT_CAT_MALT        } from '../../modules/nf-core/cat/cat/main'

workflow METAGENOMICS_PROFILING {

    take:
    ch_reads
    ch_database

    main:
    ch_versions             = Channel.empty()
    ch_multiqc_files        = Channel.empty()
    ch_postprocessing_input = Channel.empty()

    /*
        PREPARE PROFILER INPUT CHANNELS & RUN PROFILING
    */

    // Each tool has a slightly different input structure and generally separate
    // input channels for reads vs database. We restructure the channel tuple
    // for each tool and make liberal use of multiMap to keep reads/database
    // channel element order in sync with each other

    if ( params.metagenomics_profiling_tool == 'malt' ) {

        // Optional parallel run of malt available:
        // If parallel execution, split into groups with meta id of the first library id of group
        // Merging of maltlog will be done by concatenation

        // If no parallel execution (default):
        // Reset entire input meta for MALT to just database name,
        // as we don't run run on a per-sample basis due to huge databases
        // so all samples are in one run and so sample-specific metadata
        // unnecessary. Set as database name to prevent `null` job ID and prefix.

        ch_reads.branch{
            ss: it[0].strandedness == 'single'
            ds: true
        }.set { ch_reads_stranded }

        if ( params.metagenomics_malt_group_size > 0 ) {
            ch_labels_for_malt_tmp = ch_reads
                .map { meta, reads -> meta }
                .collate(params.metagenomics_malt_group_size)
                .map(meta -> meta.first().library_id )

            ch_input_for_malt_tmp =  ch_reads
                .map { meta, reads -> reads }
                .collate( params.metagenomics_malt_group_size ) //collate into bins of defined lengths
                .map{
                    reads ->
                    // add new meta with db-name as id
                    [[label: file(params.metagenomics_profiling_database).getBaseName() ], reads]
                }
                .combine(ch_database)
                .merge(ch_labels_for_malt_tmp) //combine with database
                .multiMap{
                    // and split apart again
                    meta, reads, database, ids ->
                        reads: [meta + ['id':ids], reads]
                        database: database
                }

            ch_input_for_malt = ch_input_for_malt_tmp.reads
            ch_database = ch_input_for_malt_tmp.database
        }

        else {
            // group the double-stranded entries
            // reduce the meta to the bare minimum common-information
            ch_malt_input_ds = ch_reads_stranded.ds.map{ meta, reads ->
                [
                    [label: file(params.metagenomics_profiling_database).getBaseName(), id: 'all_ds', strandedness:'double' ],
                    reads
                ]
            }
            .groupTuple(by:0)
            // group the single-stranded entries
            // reduce the meta to the bare minimum common-information
            ch_malt_input_ss = ch_reads_stranded.ss.map{ meta, reads ->
                [
                    [label: file(params.metagenomics_profiling_database).getBaseName(), id: 'all_ss', strandedness:'single' ],
                    reads
                ]
            }
            .groupTuple(by:0)
            // combine to one channel again (to run MALT twice)
            ch_input_for_malt = ch_malt_input_ds.concat(ch_malt_input_ss)
            // combine with the database
            ch_input_for_malt = ch_input_for_malt.combine(ch_database)
        }

        // Run MALT
        // Split Channels into reads and database
        ch_input_for_malt = ch_input_for_malt.multiMap{ meta, reads, database ->
            reads: [meta, reads]
            database: database
        }

        MALT_RUN ( ch_input_for_malt.reads, ch_input_for_malt.database )

        ch_maltrun_for_megan = MALT_RUN.out.rma6
            .transpose()
            .map {
                meta, rma ->
                    // re-extract meta from file names, use filename without rma to
                    // ensure we keep paired-end information in downstream filenames
                    // when no pair-merging
                    [
                        meta+['db_name':meta.id, 'id': rma.baseName],
                        rma
                    ]
            }

        ch_maltrun_for_maltextract = MALT_RUN.out.rma6.map {
            id,rma6 -> rma6
        }
        .collect()
        .toList()

        // Recombine log files for outputting if parallel execution was run
        if ( params.metagenomics_malt_group_size > 0 ) {
            ch_log_for_cat =
                MALT_RUN.out.log
                    .map {
                        meta,log -> log
                    }
                    .collect()
                    .map {
                        log -> [['id': file(params.metagenomics_profiling_database).getBaseName()], log]
                    }

            CAT_CAT_MALT ( ch_log_for_cat )
        }

        ch_maltrun_for_postprocessing = ch_maltrun_for_megan.combine(ch_maltrun_for_maltextract)

        ch_versions             = MALT_RUN.out.versions.first()
        ch_multiqc_files        = MALT_RUN.out.log
        ch_postprocessing_input = ch_maltrun_for_postprocessing
    }

    else if ( params.metagenomics_profiling_tool == 'metaphlan' ) {

        reads = reads.combine(database)
        metaphlan_reads = reads.map{ meta, reads, database -> [meta, reads] }
        metaphlan_db = reads.map{ meta, reads, database -> [database] }

        METAPHLAN_METAPHLAN ( metaphlan_reads , metaphlan_db )
        ch_versions             = METAPHLAN_METAPHLAN.out.versions.first()
        ch_postprocessing_input = METAPHLAN_METAPHLAN.out.profile

    }

    else if ( params.metagenomics_profiling_tool == 'krakenuniq' ) {
        // run krakenuniq once for all samples

        ch_reads = ch_reads.map{ meta, file -> file }
            .collect()
            .map{files -> [
                ['single_end':true], files
            ]}

        KRAKENUNIQ_PRELOADEDKRAKENUNIQ (
            ch_reads,
            ch_database,
            params.metagenomics_krakenuniq_ramchunksize,
            params.metagenomics_kraken_savereads,
            true, // save read assignments
            params.metagenomics_kraken_savereadclassifications
        )

        ch_versions             = KRAKENUNIQ_PRELOADEDKRAKENUNIQ.out.versions
        ch_multiqc_files        = KRAKENUNIQ_PRELOADEDKRAKENUNIQ.out.report
        ch_postprocessing_input = KRAKENUNIQ_PRELOADEDKRAKENUNIQ.out.report

        KRAKENUNIQ_PRELOADEDKRAKENUNIQ.out.report.view()
    }

    else if ( params.metagenomics_profiling_tool == 'kraken2' ) {
        // run kraken2 per sample
        // it lacks the option of krakenuniq

        ch_reads = ch_reads.combine(ch_database)
        ch_kraken2_reads = ch_reads.map{meta, reads, database -> [meta, reads]}
        ch_kraken2_db = ch_reads.map{meta, reads, database -> [database]}

        KRAKEN2_KRAKEN2 (
            ch_kraken2_reads,
            ch_kraken2_db,
            params.metagenomics_kraken_savereads,
            params.metagenomics_kraken_savereadclassifications
        )

        ch_multiqc_files        = KRAKEN2_KRAKEN2.out.report
        ch_versions             = KRAKEN2_KRAKEN2.out.versions.first()
        ch_postprocessing_input = KRAKEN2_KRAKEN2.out.report
    }

    emit:
    versions             = ch_versions             // channel: [ versions.yml ]
    postprocessing_input = ch_postprocessing_input // channel: [ val(meta), [ inputs_for_postprocessing_tools ] ] // see info at metagenomics_postprocessing
    mqc                  = ch_multiqc_files

}
