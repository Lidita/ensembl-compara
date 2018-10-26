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

=head1 NAME

Bio::EnsEMBL::Compara::PipeConfig::ProteinTrees_conf

=head1 DESCRIPTION

    Add/update all species to master database


=head1 SYNOPSIS

    #1. fetch all species from REST
    #2. add all to master_db

=head1 AUTHORSHIP

Ensembl Team. Individual contributions can be found in the GIT log.

=head1 APPENDIX

The rest of the documentation details each of the object methods.
Internal methods are usually preceded with an underscore (_)

=cut

package Bio::EnsEMBL::Compara::PipeConfig::LoadAllSpeciesIntoMaster_conf;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Version 2.4;

use Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf;
use base ('Bio::EnsEMBL::Compara::PipeConfig::ComparaGeneric_conf');

sub no_compara_schema {};

sub default_options {
    my ($self) = @_;

    return {
        %{$self->SUPER::default_options},   # inherit the generic ones

        #'email'                     => $self->o('ENV', 'USER').'@ebi.ac.uk',
        'host'                      => 'mysql-ens-compara-prod-4:4401',
        #'master_db_ro'              => 'mysql://ensro\@mysql-ens-compara-prod-4:4401/treefam_master',
        #'registry_source'           => $self->o('ensembl_cvs_root_dir').'/ensembl-compara/scripts/pipeline/',
        #'update_genome_bin'         => $self->o('ensembl_cvs_root_dir').'/ensembl-compara/scripts/pipeline/update_genome.pl',
    };
}


# This section has to be filled in any derived class
sub resource_classes {
    my ($self) = @_;
    return {
        %{$self->SUPER::resource_classes},  # inherit 'default' from the parent class

         '250Mb_job'        => {'LSF' => '-C0 -M250   -R"select[mem>250]   rusage[mem=250]"' },
         '500Mb_job'        => {'LSF' => '-C0 -M500   -R"select[mem>500]   rusage[mem=500]"' },
         '1Gb_job'          => {'LSF' => '-C0 -M1000  -R"select[mem>1000]  rusage[mem=1000]"' },
         '2Gb_job'          => {'LSF' => '-C0 -M2000  -R"select[mem>2000]  rusage[mem=2000]"' },
         '4Gb_job'          => {'LSF' => '-C0 -M4000  -R"select[mem>4000]  rusage[mem=4000]"' },
         '8Gb_job'          => {'LSF' => '-C0 -M8000  -R"select[mem>8000]  rusage[mem=8000]"' },
    };
}


sub pipeline_wide_parameters {  
# these parameter values are visible to all analyses, can be overridden by parameters{} and input_id{}
    my ($self) = @_;
    return {
        %{$self->SUPER::pipeline_wide_parameters},          # here we inherit anything from the base class

        'ensembl_release'   => $self->o('ensembl_release'),
    };
}


sub pipeline_analyses {
    my ($self) = @_;

    return [

        {   -logic_name => 'START',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::AssertMatchingVersions',
            -parameters => {
                'db_conn'    => $self->o('master_db'),
            },
            -input_ids  => [ {
                    'production_db_url' => 'mysql://anonymous@ensembldb.ensembl.org:3306/ensembl_production_92',
                } ],
            -flow_into      => [ 'get_species_list' ],
        },

        {   -logic_name => 'get_species_list',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
            -parameters => {
                'db_conn'       => '#production_db_url#',
                'inputquery'    => 'SELECT production_name AS species_name FROM db JOIN species USING (species_id) WHERE db_release=#ensembl_release# AND db_type="core"',
            },
            -flow_into => {
                '2->A' => [ 'update_species_in_master'  ],
                'A->1' => [ 'create_collection' ], 
            },
        },

        {   -logic_name => 'update_species_in_master',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::RunUpdateGenome',
            -parameters => {
                'compara_db'    => $self->o('master_db'),
                'registry_conf' => $self->o('registry_conf'),
            },
            -hive_capacity => 10,
            -flow_into => {
                3 => [ '?accu_name=updated_genome_db_ids&accu_address=[]&accu_input_variable=genome_db_id'  ],
            },

        },

        {   -logic_name => 'create_collection',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::CreateCollection',
            -parameters => {
                #'registry_source'           => $self->o('registry_source'),
                #'collection_name'           => $self->o('new_collection_name'),
                'master_db'                 => $self->o('master_db'),
            },
            -hive_capacity => 30,
            -flow_into  => [ 'backbone_pipeline_finished' ],
        },

        {   -logic_name => 'backbone_pipeline_finished',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
        },

    ];
}

1;

