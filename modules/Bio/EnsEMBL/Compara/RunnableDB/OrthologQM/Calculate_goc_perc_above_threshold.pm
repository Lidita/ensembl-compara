=head1 LICENSE

Copyright [1999-2016] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

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

   Bio::EnsEMBL::Compara::RunnableDB::OrthologQM::Calculate_goc_perc_above_threshold

=head1 SYNOPSIS

=head1 DESCRIPTION
use the genetic distance of a pair species to determine what the goc threshold should be. 

Example run

  standaloneJob.pl Bio::EnsEMBL::Compara::RunnableDB::OrthologQM::Calculate_goc_perc_above_threshold -mlss_id -threshold

=cut

package Bio::EnsEMBL::Compara::RunnableDB::OrthologQM::Calculate_goc_perc_above_threshold;

use strict;
use warnings;
use Data::Dumper;

use base ('Bio::EnsEMBL::Compara::RunnableDB::BaseRunnable');

use Bio::EnsEMBL::Registry;


=head2 param_defaults

    Description : Implements param_defaults() interface method of Bio::EnsEMBL::Hive::Process that defines module defaults for parameters. Lowest level parameters

=cut

sub param_defaults {
    my $self = shift;
    return {
            %{ $self->SUPER::param_defaults() },
#		'mlss_id'	=>	'100021',
#		'compara_db' => 'mysql://ensro@compara4/OrthologQM_test_db',
#		'compara_db' => 'mysql://ensro@compara4/wa2_protein_trees_84'
#    'compara_db' => 'mysql://ensro@compara5/cc21_ensembl_compara_84'
    };
}



sub fetch_input {
	my $self = shift;
  my $mlss_id = $self->param_required('mlss_id');
  my $query = "SELECT goc_score , COUNT(*) FROM homology where method_link_species_set_id =$mlss_id GROUP BY goc_score";
  my $goc_distribution = $self->compara_dba->dbc->db_handle->selectall_arrayref($query);
  $self->param('goc_dist', $goc_distribution);
#  print Dumper($self->param('goc_dist'));
  my $thresh = $self->param_required('threshold');
	$self->param('thresh', $thresh);
}

sub run {
  my $self = shift;

  $self->param('perc_above_thresh', $self->_calculate_perc());
#  print "\n\n"  , $self->param('perc_above_thresh') , "\n\n";
}

sub write_output {
  	my $self = shift @_;
#    print $self->param('threshold');
    $self->dataflow_output_id( {'perc_above_thresh' => $self->param('perc_above_thresh'), 'goc_dist' => $self->param('goc_dist')} , 1);
}


sub _calculate_perc {
  my $self = shift @_;
  my ($total, $above_thresh_total);
  foreach my $dist (@{$self->param('goc_dist')}) {
    if (!$dist->[0]) {
      next;
    }
    else{
      $total += $dist->[1];

      if ($dist->[0] >= $self->param('thresh')) {
        $above_thresh_total += $dist->[1];
      }

    }
  }

  my $perc_above_thresh = ($above_thresh_total/$total) * 100;
  return $perc_above_thresh;
}

1;