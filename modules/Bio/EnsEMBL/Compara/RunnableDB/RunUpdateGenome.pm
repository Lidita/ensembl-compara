
=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2019] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

=head1 CONTACT

Please email comments or questions to the public Ensembl
developers list at <http://lists.ensembl.org/mailman/listinfo/dev>.

Questions may also be sent to the Ensembl help desk at
<http://www.ensembl.org/Help/Contact>.

=cut

=head1 NAME

Bio::EnsEMBL::Compara::RunnableDB::RunUpdateGenome

=head1 SYNOPSIS

This runnable is used to:
    1 - run update_genome.pl


=head1 DESCRIPTION

This Analysis/RunnableDB is designed to run update_genome.pl

=cut

=head1 APPENDIX

The rest of the documentation details each of the object methods.
Internal methods are usually preceded with a "_"

=cut

package Bio::EnsEMBL::Compara::RunnableDB::RunUpdateGenome;

use strict;
use warnings;

use Bio::EnsEMBL::Compara::Utils::MasterDatabase;

use base ('Bio::EnsEMBL::Compara::RunnableDB::BaseRunnable');

sub param_defaults {
    my $self = shift @_;
    return {
        %{ $self->SUPER::param_defaults() },

        # Should we set first_release and unset last_release ?
        'release_genome'        => 1,
        # Species for which we allow non-reference DnaFrags to be missing/added
        'species_with_patches'  => [ 'homo_sapiens', 'mus_musculus', 'danio_rerio' ],
        # Do we check that the DnaFrags of existing genomes are still correct ?
        'verify_dnafrags'       => 1,
    };
}

sub fetch_input {
    my $self = shift @_;

    $self->load_registry( $self->param('registry_conf') );

    my $species = $self->param_required('species_name');
    my $species_no_underscores = $species;
    $species_no_underscores =~ s/\_/\ /;

    my $species_dba = Bio::EnsEMBL::Registry->get_DBAdaptor($species, "core")
                      || Bio::EnsEMBL::Registry->get_DBAdaptor($species_no_underscores, "core");
    throw ("Cannot connect to database [${species_no_underscores} or ${species}]") unless $species_dba;

    my $genome_db_adaptor = $self->compara_dba->get_GenomeDBAdaptor();
    my $genome_db = eval {$genome_db_adaptor->fetch_by_core_DBAdaptor($species_dba)};

    $self->param('genome_db', $genome_db);
    $self->param('species_dba', $species_dba);
}

sub run {
    my $self = shift @_;

    my $genome_db   = $self->param('genome_db');
    my $species_dba = $self->param('species_dba');

    $self->param('all_genome_dbs', []);
    $self->param('new_genome_dbs', []);
    $self->param('new_patches', []);

    # Run in a transaction not to leave the database in an incomplete state
    $self->call_within_transaction( sub {
        # Process the genome and all its components (if any)
        $genome_db = $self->process_genome($genome_db, $species_dba);
        foreach my $c (@{$species_dba->get_GenomeContainer->get_genome_components}) {
            $self->process_genome($genome_db, $species_dba, $c);
        }
    } );
}


sub write_output {
    my $self = shift;

    foreach my $genome_db (@{$self->param('new_genome_dbs')}) {
        $self->dataflow_output_id( $genome_db->dbID, 2 );
    }
    foreach my $genome_db (@{$self->param('new_patches')}) {
        $self->dataflow_output_id( $genome_db->dbID, 3 );
    }
}


##########################################
#
# internal methods
#
##########################################

sub process_genome {
    my $self = shift @_;
    my ($genome_db, $species_dba, $genome_component) = @_;

    if ($genome_db) {
        $genome_db = $genome_db->component_genome_dbs($genome_component) if $genome_component;

        my $proper_genome_db = Bio::EnsEMBL::Compara::GenomeDB->new_from_DBAdaptor($species_dba);

        my $diff_genome_db = $proper_genome_db->_check_equals($genome_db);
        if ($diff_genome_db) {
            $proper_genome_db->first_release($genome_db->first_release);
            $proper_genome_db->adaptor($genome_db->adaptor);
            $self->say_with_header('Fixing genome_db '.$genome_db->toString);
            $proper_genome_db->dbID($genome_db->dbID);
            $genome_db->adaptor->update($proper_genome_db);
            $genome_db = $proper_genome_db;
            $self->say_with_header('genome_db now is '.$genome_db->toString);
        }

        my $is_species_with_patches = scalar(grep {$genome_db->name eq $_} @{$self->param_required('species_with_patches')});

        # Check that the reference DnaFrags are identical
        if ($self->param('compare_dnafrags')) {
            my $diff_dnafrags = Bio::EnsEMBL::Compara::Utils::MasterDatabase::compare_dnafrags($self->compara_dba, $genome_db, $species_dba, $is_species_with_patches);
            $self->throw('Missing/extra/different for the genome '.$genome_db->name.' : '.join(',', @$diff_dnafrags)) if scalar(@$diff_dnafrags);
        }

        if ($is_species_with_patches) {

            # Load the new non-reference DnaFrags
            my $new_dnafrags = Bio::EnsEMBL::Compara::Utils::MasterDatabase::update_dnafrags($self->compara_dba, $genome_db, $species_dba, 'only_non_reference');

            # Register the changes
            push @{$self->param('new_patches')}, $genome_db if $new_dnafrags;

        }
    } else {

        # Build a new GenomeDB
        $genome_db = Bio::EnsEMBL::Compara::GenomeDB->new_from_DBAdaptor($species_dba);

        # Basic safety checks
        unless (defined($genome_db->name)) {
            $self->throw("Cannot find species.production_name in meta table for ".($species_dba->locator));
        }
        unless (defined($genome_db->taxon_id)) {
            $self->throw("Cannot find species.taxonomy_id in meta table for ".($species_dba->locator));
        }

        # Store in the database
        $self->compara_dba->get_GenomeDBAdaptor->store($genome_db);
        $self->say_with_header('Stored '.$genome_db->toString);
        my $new_dnafrags = Bio::EnsEMBL::Compara::Utils::MasterDatabase::update_dnafrags($self->compara_dba, $genome_db, $species_dba);
        $self->say_with_header("Found $new_dnafrags DnaFrags in " . $species_dba->dbc->host . "/" . $species_dba->dbc->dbname);

        push @{$self->param('new_genome_dbs')}, $genome_db;
    }

    $genome_db->adaptor->make_object_current($genome_db) if $self->param('release_genome');

    push @{$self->param('all_genome_dbs')}, $genome_db;
    return $genome_db;
}


1;
