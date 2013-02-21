=pod 

=head1 NAME

Bio::EnsEMBL::BuildHMMprofiles::RunnableDB::HmmProfileFactory

=cut

=head1 DESCRIPTION

 This module create a hmmbuild job for each multiple alignment output

=cut
package Bio::EnsEMBL::BuildHMMprofiles::RunnableDB::HmmProfileFactory;

use strict;
use warnings;

use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use Bio::Perl;

use base ('Bio::EnsEMBL::Compara::RunnableDB::BaseRunnable');

=head2 fetch_input

    Title   :   fetch_input
    Usage   :   $self->fetch_input
    Function:   Retrieving required parameters
    Returns :   none
    Args    :   none

=cut
my $msa_dir;

sub fetch_input {
    my $self = shift @_;
    
    $msa_dir     = $self->param('msa_dir');

return;
}

=head2 run

  Arg[1]     : -none-
  Example    : $self->run;
  Function   : Retrieve list of msa output and create hmmbuild job
               for each file
  Returns    : 1 on successful completion
  Exceptions : dies if runnable throws an unexpected error

=cut
sub run {
    my $self = shift @_;

    opendir(DIR, $msa_dir) or die "Error openining dir '$msa_dir' : $!";
    my @msa_subdir = readdir DIR;
   
    foreach my $msa_subdir (@msa_subdir){
      
      next unless $msa_subdir =~/^msa/;  
      my $dir = $msa_dir.'/'.$msa_subdir;
      opendir(DIR_2, $dir) or die "Error openining dir '$dir' : $!";

      while ((my $filename = readdir (DIR_2))) {

        next unless $filename =~/^cluster/;

        $filename = $dir.'/'.$filename;
	 	
        $self->dataflow_output_id( { 'msa' => $filename }, 2 ); 

        } 
    }
return;
}

sub write_output {
    my $self = shift @_;

return;
}

1;
