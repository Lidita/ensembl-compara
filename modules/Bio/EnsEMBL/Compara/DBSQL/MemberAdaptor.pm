=head1 LICENSE

Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

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

Bio::EnsEMBL::Compara::DBSQL::MemberAdaptor

=head1 DESCRIPTION

Base adaptor for Member objects that cannot be instantiated directly

The methods are still available for compatibility until release 74 (included),
but the Member object should not be explicitely used.

=head1 INHERITANCE TREE

  Bio::EnsEMBL::Compara::DBSQL::MemberAdaptor
  +- Bio::EnsEMBL::Compara::DBSQL::BaseAdaptor

=head1 AUTHORSHIP

Ensembl Team. Individual contributions can be found in the GIT log.

=head1 APPENDIX

The rest of the documentation details each of the object methods.
Internal methods are usually preceded with an underscore (_)

=cut


package Bio::EnsEMBL::Compara::DBSQL::MemberAdaptor;

use strict; 
use warnings;


use Bio::EnsEMBL::Utils::Scalar qw(:all);
use Bio::EnsEMBL::Utils::Argument qw(rearrange);
use Bio::EnsEMBL::Utils::Exception qw(throw warning stack_trace_dump deprecate);
use DBI qw(:sql_types);

use base qw(Bio::EnsEMBL::Compara::DBSQL::BaseAdaptor);




#
# GLOBAL METHODS
#
#####################


=head2 fetch_by_source_stable_id

  Arg [1]    : (optional) string $source_name
  Arg [2]    : string $stable_id
  Example    : my $member = $ma->fetch_by_source_stable_id(
                   "Uniprot/SWISSPROT", "O93279");
  Example    : my $member = $ma->fetch_by_source_stable_id(
                   undef, "O93279");
  Description: Fetches the member corresponding to this $stable_id.
               Although two members from different sources might
               have the same stable_id, this never happens in a normal
               compara DB. You can set the first argument to undef
               like in the second example.
  Returntype : Bio::EnsEMBL::Compara::Member object
  Exceptions : throws if $stable_id is undef
  Caller     : 

=cut

sub fetch_by_source_stable_id {
  my ($self,$source_name, $stable_id) = @_;

  unless(defined $stable_id) {
    throw("fetch_by_source_stable_id must have an stable_id");
  }

  #construct a constraint like 't1.table1_id = 1'
  my $constraint = '';
  if ($source_name) {
    $constraint = 'm.source_name = ? AND ';
    $self->bind_param_generic_fetch($source_name, SQL_VARCHAR);
  }
  $constraint .= 'm.stable_id = ?';
  $self->bind_param_generic_fetch($stable_id, SQL_VARCHAR);

  return $self->generic_fetch_one($constraint);
}


=head2 fetch_all_by_source_stable_ids

  Arg [1]    : (optional) string $source_name
  Arg [2]    : arrayref of string $stable_id
  Example    : my $members = $ma->fetch_by_source_stable_id(
                   "Uniprot/SWISSPROT", ["O93279", "O62806"]);
  Description: Fetches the members corresponding to all the $stable_id.
  Returntype : arrayref Bio::EnsEMBL::Compara::Member object
  Caller     : 

=cut

sub fetch_all_by_source_stable_ids {
  my ($self,$source_name, $stable_ids) = @_;
  return [] if (!$stable_ids or !@$stable_ids);

  #construct a constraint like 't1.table1_id = 1'
  my $constraint = "";
  $constraint = "m.source_name = '$source_name' AND " if ($source_name);
  $constraint .= "m.stable_id IN ('".join("','", @$stable_ids). "')";

  #return first element of generic_fetch list
  my $obj = $self->generic_fetch($constraint);
  return $obj;
}


=head2 fetch_all

  Arg        : None
  Example    : my $members = $ma->fetch_all;
  Description: Fetch all the members in the db
               WARNING: Depending on the database where this method is called,
                        it can return a lot of data (objects) that has to be kept in memory.
                        Make sure you don't ask for more data than you can handle.
                        To access this data in a safer way, use fetch_all_Iterator instead.
  Returntype : listref of Bio::EnsEMBL::Compara::Member objects
  Exceptions : 
  Caller     : 

=cut

sub fetch_all {
  my $self = shift;

  return $self->generic_fetch();
}


=head2 fetch_all_Iterator

  Arg        : (optional) int $cache_size
  Example    : my $memberIter = $memberAdaptor->fetch_all_Iterator();
               while (my $member = $memberIter->next) {
                  #do something with $member
               }
  Description: Returns an iterator over all the members in the database
               This is safer than fetch_all for large databases.
  Returntype : Bio::EnsEMBL::Utils::Iterator
  Exceptions : 
  Caller     : 
  Status     : Experimental

=cut

sub fetch_all_Iterator {
    my ($self, $cache_size) = @_;
    return $self->generic_fetch_Iterator($cache_size,"");
}


=head2 fetch_all_by_source_Iterator

  Arg[1]     : string $source_name
  Arg[2]     : (optional) int $cache_size
  Example    : my $memberIter = $memberAdaptor->fetch_all_by_source_Iterator("ENSEMBLGENE");
               while (my $member = $memberIter->next) {
                  #do something with $member
               }
  Description: Returns an iterator over all the members corresponding
               to a source_name in the database.
               This is safer than fetch_all_by_source for large databases.
  Returntype : Bio::EnsEMBL::Utils::Iterator
  Exceptions : 
  Caller     : 
  Status     : Experimental

=cut

sub fetch_all_by_source_Iterator {
    my ($self, $source_name, $cache_size) = @_;
    throw("source_name arg is required\n") unless ($source_name);
    return $self->generic_fetch_Iterator($cache_size, "m.source_name = '$source_name'");
}


=head2 fetch_all_by_source

  Arg [1]    : string $source_name
  Example    : my $members = $ma->fetch_all_by_source(
                   "Uniprot/SWISSPROT");
  Description: Fetches the member corresponding to a source_name.
                WARNING: Depending on the database and the "source"
                where this method is called, it can return a lot of data (objects)
                that has to be kept in memory. Make sure you don't ask
                for more data than you can handle.
                To access this data in a safer way, use fetch_all_by_source_Iterator instead.
  Returntype : listref of Bio::EnsEMBL::Compara::Member objects
  Exceptions : throws if $source_name is undef
  Caller     :

=cut

sub fetch_all_by_source {
  my ($self,$source_name) = @_;

  throw("source_name arg is required\n")
    unless ($source_name);

  my $constraint = "m.source_name = '$source_name'";

  return $self->generic_fetch($constraint);
}


=head2 fetch_all_by_source_taxon

  Arg [1]    : string $source_name
  Arg [2]    : int $taxon_id
  Example    : my $members = $ma->fetch_all_by_source_taxon(
                   "Uniprot/SWISSPROT", 9606);
  Description: Fetches the member corresponding to a source_name and a taxon_id.
  Returntype : listref of Bio::EnsEMBL::Compara::Member objects
  Exceptions : throws if $source_name or $taxon_id is undef
  Caller     : 

=cut

sub fetch_all_by_source_taxon {
  my ($self,$source_name,$taxon_id) = @_;

  throw("source_name and taxon_id args are required") 
    unless($source_name && $taxon_id);

    $self->bind_param_generic_fetch($source_name, SQL_VARCHAR);
    $self->bind_param_generic_fetch($taxon_id, SQL_INTEGER);
    return $self->generic_fetch('m.source_name = ? AND m.taxon_id = ?');
}


=head2 fetch_all_by_source_genome_db_id

  Arg [1]    : string $source_name
  Arg [2]    : int $genome_db_id
  Example    : my $members = $ma->fetch_all_by_source_genome_db_id(
                   "Uniprot/SWISSPROT", 90);
  Description: Fetches the member corresponding to a source_name and a genome_db_id.
  Returntype : listref of Bio::EnsEMBL::Compara::Member objects
  Exceptions : throws if $source_name or $genome_db_id is undef
  Caller     : 

=cut

sub fetch_all_by_source_genome_db_id {
  my ($self,$source_name,$genome_db_id) = @_;

  throw("source_name and genome_db_id args are required") 
    unless($source_name && $genome_db_id);

    $self->bind_param_generic_fetch($source_name, SQL_VARCHAR);
    $self->bind_param_generic_fetch($genome_db_id, SQL_INTEGER);
    return $self->generic_fetch('m.source_name = ? AND m.genome_db_id = ?');
}


sub _fetch_all_by_source_taxon_chr_name_start_end_strand_limit {
  my ($self,$source_name,$taxon_id,$chr_name,$chr_start,$chr_end,$chr_strand,$limit) = @_;

  $self->throw("all args are required") 
      unless($source_name && $taxon_id && $chr_start && $chr_end && $chr_strand && defined ($chr_name));

  my $constraint = "m.source_name = '$source_name' and m.taxon_id = $taxon_id 
                    and m.chr_name = '$chr_name' 
                    and m.chr_start >= $chr_start and m.chr_start <= $chr_end and m.chr_end <= $chr_end 
                    and m.chr_strand = $chr_strand";

  return $self->generic_fetch($constraint, undef, defined $limit ? "LIMIT $limit" : "");
}


=head2 get_source_taxon_count

  Arg [1]    : string $source_name
  Arg [2]    : int $taxon_id
  Example    : my $sp_gene_count = $memberDBA->get_source_taxon_count('ENSEMBLGENE',$taxon_id);
  Description: Returns the number of members for this source_name and taxon_id
  Returntype : int
  Exceptions : undefined arguments

=cut

sub get_source_taxon_count {
  my ($self,$source_name,$taxon_id) = @_;

  throw("source_name and taxon_id args are required") 
    unless($source_name && $taxon_id);

    my @tabs = $self->_tables;
  my $sth = $self->prepare
    ("SELECT COUNT(*) FROM $tabs[0][0] WHERE source_name=? AND taxon_id=?");
  $sth->execute($source_name, $taxon_id);
  my ($count) = $sth->fetchrow_array();
  $sth->finish;

  return $count;
}



=head2 fetch_all_by_MemberSet

  Arg[1]     : MemberSet $set
               Currently supported: Family, Homology and GeneTree
  Example    : $family_members = $m_adaptor->fetch_all_by_MemberSet($family);
  Description: Fetches from the database all the members attached to this set
  Returntype : arrayref of Bio::EnsEMBL::Compara::Member
  Exceptions : argument not a MemberSet
  Caller     : general

=cut

sub fetch_all_by_MemberSet {
    my ($self, $set) = @_;
    assert_ref($set, 'Bio::EnsEMBL::Compara::MemberSet');
    if (UNIVERSAL::isa($set, 'Bio::EnsEMBL::Compara::AlignedMemberSet')) {
        return $self->db->get_AlignedMemberAdaptor->fetch_all_by_AlignedMemberSet($set);
    } else {
        throw("$self is not a recognized MemberSet object\n");
    }
}



#
# INTERNAL METHODS
#
###################


sub _objs_from_sth {
  my ($self, $sth) = @_;

  my @members = ();

  while(my $rowhash = $sth->fetchrow_hashref) {
    my $member = $self->create_instance_from_rowhash($rowhash);
    push @members, $member;
  }
  $sth->finish;
  return \@members
}




1;

