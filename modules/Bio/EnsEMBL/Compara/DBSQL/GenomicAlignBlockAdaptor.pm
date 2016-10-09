=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016] EMBL-European Bioinformatics Institute

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

Bio::EnsEMBL::DBSQL::Compara::GenomicAlignBlockAdaptor

=head1 SYNOPSIS

=head2 Connecting to the database using the Registry

  use Bio::EnsEMBL::Registry;

  my $reg = "Bio::EnsEMBL::Registry";

  $reg->load_registry_from_db(-host=>"ensembldb.ensembl.org", -user=>"anonymous");

  my $genomic_align_block_adaptor = $reg->get_adaptor(
      "Multi", "compara", "GenomicAlignBlock");

=head2 Store/Delete data from the database

  $genomic_align_block_adaptor->store($genomic_align_block);

  $genomic_align_block_adaptor->delete_by_dbID($genomic_align_block->dbID);

=head2 Retrieve data from the database

  $genomic_align_block = $genomic_align_block_adaptor->fetch_by_dbID(12);

  $genomic_align_blocks = $genomic_align_block_adaptor->fetch_all_by_MethodLinkSpeciesSet(
      $method_link_species_set);

  $genomic_align_blocks = $genomic_align_block_adaptor->fetch_all_by_MethodLinkSpeciesSet_Slice(
      $method_link_species_set, $human_slice);

  $genomic_align_blocks = $genomic_align_block_adaptor->fetch_all_by_MethodLinkSpeciesSet_DnaFrag(
      $method_link_species_set, $human_dnafrag);

  $genomic_align_blocks = $genomic_align_block_adaptor->fetch_all_by_MethodLinkSpeciesSet_DnaFrag_DnaFrag(
      $method_link_species_set, $human_dnafrag, undef, undef, $mouse_dnafrag, undef, undef);

  $genomic_align_block_ids = $genomic_align_block_adaptor->fetch_all_dbIDs_by_MethodLinkSpeciesSet_Dnafrag(
     $method_link_species_set, $human_dnafrag);

=head2 Other methods

$genomic_align_block = $genomic_align_block_adaptor->
    retrieve_all_direct_attributes($genomic_align_block);

$genomic_align_block_adaptor->lazy_loading(1);

=head1 DESCRIPTION

This module is intended to access data in the genomic_align_block table.

Each alignment is represented by Bio::EnsEMBL::Compara::GenomicAlignBlock. Each GenomicAlignBlock
contains several Bio::EnsEMBL::Compara::GenomicAlign, one per sequence included in the alignment.
The GenomicAlign contains information about the coordinates of the sequence and the sequence of
gaps, information needed to rebuild the aligned sequence. By combining all the aligned sequences
of the GenomicAlignBlock, it is possible to get the orignal alignment back.

=head1 INHERITANCE

This class inherits all the methods and attributes from Bio::EnsEMBL::DBSQL::BaseAdaptor

=head1 SEE ALSO

 - Bio::EnsEMBL::Registry
 - Bio::EnsEMBL::DBSQL::BaseAdaptor
 - Bio::EnsEMBL::BaseAdaptor
 - Bio::EnsEMBL::Compara::GenomicAlignBlock
 - Bio::EnsEMBL::Compara::GenomicAlign
 - Bio::EnsEMBL::Compara::GenomicAlignGroup,
 - Bio::EnsEMBL::Compara::MethodLinkSpeciesSet
 - Bio::EnsEMBL::Compara::DBSQL::MethodLinkSpeciesSetAdaptor
 - Bio::EnsEMBL::Slice
 - Bio::EnsEMBL::SliceAdaptor
 - Bio::EnsEMBL::Compara::DnaFrag
 - Bio::EnsEMBL::Compara::DBSQL::DnaFragAdaptor

=head1 APPENDIX

The rest of the documentation details each of the object methods. Internal methods are usually preceded with a _

=cut


# Let the code begin...


package Bio::EnsEMBL::Compara::DBSQL::GenomicAlignBlockAdaptor;

use vars qw(@ISA);
use strict;
use warnings;

use Bio::AlignIO;
use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::EnsEMBL::Compara::GenomicAlignBlock;
use Bio::EnsEMBL::Compara::GenomicAlign;
use Bio::EnsEMBL::Compara::DnaFrag;
use Bio::EnsEMBL::Feature;
use Bio::EnsEMBL::Utils::Exception;
use Bio::EnsEMBL::Utils::Scalar qw(assert_ref);
use Bio::EnsEMBL::Compara::Utils::Cigars;

use Data::Dumper;

@ISA = qw(Bio::EnsEMBL::DBSQL::BaseAdaptor);

=head2 new

  Arg [1]    : list of args to super class constructor
  Example    : $ga_a = new Bio::EnsEMBL::Compara::GenomicAlignBlockAdaptor($dbobj);
  Description: Creates a new GenomicAlignBlockAdaptor.  The superclass 
               constructor is extended to initialise an internal cache.  This
               class should be instantiated through the get method on the 
               DBAdaptor rather than calling this method directly.
  Returntype : none
  Exceptions : none
  Caller     : Bio::EnsEMBL::DBSQL::DBConnection
  Status     : Stable

=cut

sub new {
  my $class = shift;

  my $self = $class->SUPER::new(@_);

  $self->{_lazy_loading} = 0;

  return $self;
}

=head2 store

  Arg  1     : Bio::EnsEMBL::Compara::GenomicAlignBlock
               The things you want to store
  Example    : $gen_ali_blk_adaptor->store($genomic_align_block);
  Description: It stores the given GenomicAlginBlock in the database as well
               as the GenomicAlign objects it contains
  Returntype : Bio::EnsEMBL::Compara::GenomicAlignBlock object
  Exceptions : - no Bio::EnsEMBL::Compara::MethodLinkSpeciesSet is linked
               - no Bio::EnsEMBL::Compara::GenomicAlign object is linked
               - no Bio::EnsEMBL::Compara::DnaFrag object is linked 
               - unknown method link
               - cannot lock tables
               - cannot store GenomicAlignBlock object
               - cannot store corresponding GenomicAlign objects
  Caller     : general
  Status     : Stable

=cut

sub store {
  my ($self, $genomic_align_block) = @_;

  my $genomic_align_block_sql =
        qq{INSERT INTO genomic_align_block (
                genomic_align_block_id,
                method_link_species_set_id,
                score,
                perc_id,
                length,
                group_id,
                level_id
        ) VALUES (?,?,?,?,?,?,?)};
  
  my @values;
  
  ## CHECKING
  assert_ref($genomic_align_block, 'Bio::EnsEMBL::Compara::GenomicAlignBlock', 'genomic_align_block');
  if (!defined($genomic_align_block->method_link_species_set)) {
    throw("There is no Bio::EnsEMBL::Compara::MethodLinkSpeciesSet object attached to this".
        " Bio::EnsEMBL::Compara::GenomicAlignBlock object [$self]");
  }
  if (!defined($genomic_align_block->method_link_species_set->dbID)) {
    throw("Attached Bio::EnsEMBL::Compara::MethodLinkSpeciesSet object has no dbID");
  }
  if (!$genomic_align_block->genomic_align_array or !@{$genomic_align_block->genomic_align_array}) {
    throw("This block does not contain any GenomicAlign. Nothing to store!");
  }
  foreach my $genomic_align (@{$genomic_align_block->genomic_align_array}) {
    # check if every GenomicAlgin has a dbID
    if (!defined($genomic_align->dnafrag_id)) {
      throw("dna_fragment in GenomicAlignBlock is not in DB");
    }
  }
  
  ## Stores data, all of them with the same id
  my $sth = $self->prepare($genomic_align_block_sql);
  #print $align_block_id, "\n";
  $sth->execute(
                ($genomic_align_block->dbID or undef),
                $genomic_align_block->method_link_species_set->dbID,
                $genomic_align_block->score,
                $genomic_align_block->perc_id,
                $genomic_align_block->length,
                $genomic_align_block->group_id,
		($genomic_align_block->level_id or 1)
        );
  if (!$genomic_align_block->dbID) {
    $genomic_align_block->dbID( $self->dbc->db_handle->last_insert_id(undef, undef, 'genomic_align_block', 'genomic_align_block_id') );
  }
  info("Stored Bio::EnsEMBL::Compara::GenomicAlignBlock ".
        ($genomic_align_block->dbID or "NULL").
        ", mlss=".$genomic_align_block->method_link_species_set->dbID.
        ", scr=".($genomic_align_block->score or "NA").
        ", id=".($genomic_align_block->perc_id or "NA")."\%".
        ", l=".($genomic_align_block->length or "NA").
        ", lvl=".($genomic_align_block->level_id or 1).
        "");

  ## Stores genomic_align entries
  my $genomic_align_adaptor = $self->db->get_GenomicAlignAdaptor;
  $genomic_align_adaptor->store($genomic_align_block->genomic_align_array);

  return $genomic_align_block;
}


=head2 delete_by_dbID

  Arg  1     : integer $genomic_align_block_id
  Example    : $gen_ali_blk_adaptor->delete_by_dbID(352158763);
  Description: It removes the given GenomicAlginBlock in the database as well
               as the GenomicAlign objects it contains
  Returntype : none
  Exceptions : 
  Caller     : general
  Status     : Stable

=cut

sub delete_by_dbID {
  my ($self, $genomic_align_block_id) = @_;

  my $genomic_align_block_sql =
        qq{DELETE FROM genomic_align_block WHERE genomic_align_block_id = ?};
  
  ## Deletes genomic_align_block entry 
  my $sth = $self->prepare($genomic_align_block_sql);
  $sth->execute($genomic_align_block_id);
  $sth->finish();
  
  ## Deletes corresponding genomic_align entries
  my $genomic_align_adaptor = $self->db->get_GenomicAlignAdaptor;
  $genomic_align_adaptor->delete_by_genomic_align_block_id($genomic_align_block_id);
}


=head2 fetch_by_dbID

  Arg  1     : integer $genomic_align_block_id
  Example    : my $genomic_align_block = $genomic_align_block_adaptor->fetch_by_dbID(1)
  Description: Retrieve the corresponding
               Bio::EnsEMBL::Compara::GenomicAlignBlock object
  Returntype : Bio::EnsEMBL::Compara::GenomicAlignBlock object
  Exceptions : Returns undef if no matching
               Bio::EnsEMBL::Compara::GenomicAlignBlock object can be retrieved
  Caller     : none
  Status     : Stable

=cut

sub fetch_by_dbID {
  my ($self, $dbID) = @_;
  my $genomic_align_block; # returned object

  my $sql = qq{
          SELECT
              method_link_species_set_id,
              score,
              perc_id,
              length,
              group_id
          FROM
              genomic_align_block
          WHERE
              genomic_align_block_id = ?
      };

  my $sth = $self->prepare($sql);
  $sth->execute($dbID);
  my $array_ref = $sth->fetchrow_arrayref();
  $sth->finish();
  
  if ($array_ref) {
    my ($method_link_species_set_id, $score, $perc_id, $length, $group_id) = @$array_ref;
  
    ## Create the object
    # Lazy loading of genomic_align objects. They are fetched only when needed.
    $genomic_align_block = new Bio::EnsEMBL::Compara::GenomicAlignBlock(
                          -adaptor => $self,
                          -dbID => $dbID,
                          -method_link_species_set_id => $method_link_species_set_id,
                          -score => $score,
			  -perc_id => $perc_id,
			  -length => $length,
                          -group_id => $group_id
                  );
    if (!$self->lazy_loading) {
      $genomic_align_block = $self->retrieve_all_direct_attributes($genomic_align_block);
    }
  }

  return $genomic_align_block;
}


=head2 fetch_all_dbIDs_by_MethodLinkSpeciesSet_Dnafrag

  Arg  1     : Bio::EnsEMBL::Compara::MethodLinkSpeciesSet $method_link_species_set
  Arg  2     : Bio::EnsEMBL::Compara::DnaFrag $dnafrag
  Example    : my $genomic_align_blocks_IDs =
                  $genomic_align_block_adaptor->fetch_all_dbIDs_by_MethodLinkSpeciesSet_Dnafrag(
                      $method_link_species_set, $dnafrag);
  Description: Retrieve the corresponding dbIDs as a listref of strings.
  Returntype : ref. to an array of genomic_align_block IDs (strings)
  Exceptions : Returns ref. to an empty array if no matching IDs can be found
  Caller     : $object->method_name
  Status     : Stable

=cut

sub fetch_all_dbIDs_by_MethodLinkSpeciesSet_Dnafrag {
  my ($self, $method_link_species_set, $dnafrag) = @_;

  my $genomic_align_block_ids = []; # returned object

  assert_ref($method_link_species_set, 'Bio::EnsEMBL::Compara::MethodLinkSpeciesSet', 'method_link_species_set');
  my $method_link_species_set_id = $method_link_species_set->dbID;
  throw("[$method_link_species_set_id] has no dbID") if (!$method_link_species_set_id);

  ## Check the dnafrag obj
  assert_ref($dnafrag, 'Bio::EnsEMBL::Compara::DnaFrag', 'dnafrag');

  my $dnafrag_id = $dnafrag->dbID;

  my $sql = qq{
          SELECT
              ga.genomic_align_block_id
          FROM
              genomic_align ga
          WHERE 
              ga.method_link_species_set_id = $method_link_species_set_id
          AND
              ga.dnafrag_id = $dnafrag_id 
      };

  my $sth = $self->prepare($sql);
  $sth->execute();
  my $genomic_align_block_id;
  $sth->bind_columns(\$genomic_align_block_id);
  
  while ($sth->fetch) {
    push(@$genomic_align_block_ids, $genomic_align_block_id);
  }
  
  $sth->finish();
  
  return $genomic_align_block_ids;

}

=head2 fetch_all_by_MethodLinkSpeciesSet

  Arg  1     : Bio::EnsEMBL::Compara::MethodLinkSpeciesSet $method_link_species_set
  Arg  2     : integer $limit_number [optional]
  Arg  3     : integer $limit_index_start [optional]
  Example    : my $genomic_align_blocks =
                  $genomic_align_block_adaptor->
                      fetch_all_by_MethodLinkSpeciesSet($mlss);
  Description: Retrieve the corresponding
               Bio::EnsEMBL::Compara::GenomicAlignBlock objects. Objects 
  Returntype : ref. to an array of Bio::EnsEMBL::Compara::GenomicAlignBlock objects.
               Corresponding Bio::EnsEMBL::Compara::GenomicAlign are only retrieved
               when required.
  Exceptions : Returns ref. to an empty array if no matching
               Bio::EnsEMBL::Compara::GenomicAlignBlock object can be retrieved
  Caller     : none
  Status     : Stable

=cut

sub fetch_all_by_MethodLinkSpeciesSet {
  my ($self, $method_link_species_set, $limit_number, $limit_index_start) = @_;

  my $genomic_align_blocks = []; # returned object

  assert_ref($method_link_species_set, 'Bio::EnsEMBL::Compara::MethodLinkSpeciesSet', 'method_link_species_set');
  my $method_link_species_set_id = $method_link_species_set->dbID;
  throw("[$method_link_species_set_id] has no dbID") if (!$method_link_species_set_id);

  if ( $method_link_species_set->method->type =~ /CACTUS_HAL/ ) {
      throw( "fetch_all_by_MethodLinkSpeciesSet is not supported for this method type (CACTUS_HAL)\n" );
  #       my @genome_dbs = @{ $method_link_species_set->species_set_obj->genome_dbs };
  #       my $ref_gdb = pop( @genome_dbs );

  #       my $dnafrag_adaptor = $method_link_species_set->adaptor->db->get_DnaFragAdaptor;
  #       my @ref_dnafrags = @{ $dnafrag_adaptor->fetch_all_by_GenomeDB_region( $ref_gdb ) };     

  #       my @all_gabs;
  #       foreach my $dnafrag ( @ref_dnafrags ){
  #           push( @all_gabs, $self->fetch_all_by_MethodLinkSpeciesSet_DnaFrag( $method_link_species_set, $dnafrag, undef, undef, $limit_number ) );
            
  #           # stop if $limit_number is reached!
  #           if ( defined $limit_number && scalar @all_gabs >= $limit_number ) {
  #               my $len = scalar @all_gabs;
  #               my $offset = $limit_number - $len;
  #               splice @all_gabs, $offset;
  #               last;
  #           }
  #       }

  #       return \@all_gabs;
  }
  my $sql = qq{
          SELECT
              gab.genomic_align_block_id,
              gab.score,
              gab.perc_id,
              gab.length,
              gab.group_id
          FROM
              genomic_align_block gab
          WHERE 
              gab.method_link_species_set_id = $method_link_species_set_id
      };
  if ($limit_number && $limit_index_start) {
    $sql .= qq{ LIMIT $limit_index_start , $limit_number };
  } elsif ($limit_number) {
    $sql .= qq{ LIMIT $limit_number };
  }

  my $sth = $self->prepare($sql);
  $sth->execute();
  my ($genomic_align_block_id, $score, $perc_id, $length, $group_id);
  $sth->bind_columns(\$genomic_align_block_id, \$score, \$perc_id, \$length, \$group_id);
  
  while ($sth->fetch) {
    my $this_genomic_align_block = new Bio::EnsEMBL::Compara::GenomicAlignBlock(
            -adaptor => $self,
            -dbID => $genomic_align_block_id,
            -method_link_species_set_id => $method_link_species_set_id,
            -score => $score,
            -perc_id => $perc_id,
            -length => $length,
	    -group_id => $group_id
        );
    push(@$genomic_align_blocks, $this_genomic_align_block);
  }
  
  $sth->finish();
  
  return $genomic_align_blocks;
  
}


=head2 fetch_all_by_MethodLinkSpeciesSet_Slice

  Arg  1     : Bio::EnsEMBL::Compara::MethodLinkSpeciesSet $method_link_species_set
  Arg  2     : Bio::EnsEMBL::Slice $original_slice
  Arg  3     : integer $limit_number [optional]
  Arg  4     : integer $limit_index_start [optional]
  Arg  5     : boolean $restrict_resulting_blocks [optional]
  Example    : my $genomic_align_blocks =
                  $genomic_align_block_adaptor->fetch_all_by_MethodLinkSpeciesSet_Slice(
                      $method_link_species_set, $original_slice);
  Description: Retrieve the corresponding
               Bio::EnsEMBL::Compara::GenomicAlignBlock objects. The alignments may be
               reverse-complemented in order to match the strand of the original slice. If the original_slice covers 
               non-primary regions such as PAR or PATCHES, GenomicAlignBlock objects are restricted to the relevant slice. 
  Returntype : ref. to an array of Bio::EnsEMBL::Compara::GenomicAlignBlock objects. Only dbID,
               adaptor and method_link_species_set are actually stored in the objects. The remaining
               attributes are only retrieved when required.
  Exceptions : Returns ref. to an empty array if no matching
               Bio::EnsEMBL::Compara::GenomicAlignBlock object can be retrieved
  Caller     : $object->method_name
  Status     : Stable

=cut

sub fetch_all_by_MethodLinkSpeciesSet_Slice {
  my ($self, $method_link_species_set, $reference_slice, $limit_number, $limit_index_start, $restrict) = @_;
  my $all_genomic_align_blocks = []; # Returned value

  ## method_link_species_set will be checked in the fetch_all_by_MethodLinkSpeciesSet_DnaFrag method

  ## Check original_slice
  assert_ref($reference_slice, 'Bio::EnsEMBL::Slice', 'reference_slice');

  $limit_number = 0 if (!defined($limit_number));
  $limit_index_start = 0 if (!defined($limit_index_start));

  # ## HANDLE HAL ##
  # if ( $method_link_species_set->method->type eq 'CACTUS_HAL' ) {
  #       #create dnafrag from slice and use fetch_by_MLSS_DnaFrag
  #       my $genome_db_adaptor = $method_link_species_set->adaptor->db->get_GenomeDBAdaptor;
  #       my $ref = $genome_db_adaptor->fetch_by_Slice( $reference_slice );
  #       throw( "Cannot find genome_db for slice\n" ) unless ( defined $ref );

  #       my $slice_dnafrag = Bio::EnsEMBL::Compara::DnaFrag->new_from_Slice( $reference_slice, $ref );
  #       return $self->fetch_all_by_MethodLinkSpeciesSet_DnaFrag( $method_link_species_set, $slice_dnafrag, $reference_slice->start, $reference_slice->end, $limit_number );
  # }


  if ($reference_slice->isa("Bio::EnsEMBL::Compara::AlignSlice::Slice")) {
    return $reference_slice->get_all_GenomicAlignBlocks(
        $method_link_species_set->method->type, $method_link_species_set->species_set);
  }

  ## Get the Bio::EnsEMBL::Compara::GenomeDB object corresponding to the
  ## $reference_slice
  my $slice_adaptor = $reference_slice->adaptor();
  if(!$slice_adaptor) {
    warning("Slice has no attached adaptor. Cannot get Compara alignments.");
    return $all_genomic_align_blocks;
  }

  my $genome_db_adaptor = $self->db->get_GenomeDBAdaptor;
  my $genome_db = $genome_db_adaptor->fetch_by_Slice($reference_slice);

#  my $projection_segments = $reference_slice->project('toplevel');
  my $filter_projections = 1;
  my $projection_segments = $slice_adaptor->fetch_normalized_slice_projection($reference_slice, $filter_projections);
  return [] if(!@$projection_segments);

  foreach my $this_projection_segment (@$projection_segments) {
    my $offset    = $this_projection_segment->from_start();
    my $this_slice = $this_projection_segment->to_Slice;

    my $dnafrag_type = $this_slice->coord_system->name;
    
    my $dnafrag_adaptor = $method_link_species_set->adaptor->db->get_DnaFragAdaptor;
    my $this_dnafrag    = $dnafrag_adaptor->fetch_by_Slice( $this_slice );

    next if (!$this_dnafrag);

    my $these_genomic_align_blocks = $self->fetch_all_by_MethodLinkSpeciesSet_DnaFrag(
            $method_link_species_set,
            $this_dnafrag,
            $this_slice->start,
            $this_slice->end,
            $limit_number,
            $limit_index_start,
            $restrict
        );

    #If the GenomicAlignBlock has been restricted, set up the correct values 
    #for restricted_aln_start and restricted_aln_end
    foreach my $this_genomic_align_block (@$these_genomic_align_blocks) {

    	if (defined $this_genomic_align_block->{'restricted_aln_start'}) {
	      my $tmp_start = $this_genomic_align_block->{'restricted_aln_start'};
	      #if ($reference_slice->strand != $this_genomic_align_block->reference_genomic_align->dnafrag_strand) {

	      #the start and end are always calculated for the forward strand
	      if ($reference_slice->strand == 1) {
		      $this_genomic_align_block->{'restricted_aln_start'}++;
		      $this_genomic_align_block->{'restricted_aln_end'} = $this_genomic_align_block->{'original_length'} - $this_genomic_align_block->{'restricted_aln_end'};
	      } else {
		      $this_genomic_align_block->{'restricted_aln_start'} = $this_genomic_align_block->{'restricted_aln_end'} + 1;
		      $this_genomic_align_block->{'restricted_aln_end'} = $this_genomic_align_block->{'original_length'} - $tmp_start;
	      }
	    }
    }

    my $top_slice = $slice_adaptor->fetch_by_region($dnafrag_type, 
                                                    $this_slice->seq_region_name);

    # need to convert features to requested coord system
    # if it was different then the one we used for fetching
    if($top_slice->name ne $reference_slice->name) {
      foreach my $this_genomic_align_block (@$these_genomic_align_blocks) {
        my $feature = new Bio::EnsEMBL::Feature(
                -slice => $top_slice,
                -start => $this_genomic_align_block->reference_genomic_align->dnafrag_start,
                -end => $this_genomic_align_block->reference_genomic_align->dnafrag_end,
                -strand => $this_genomic_align_block->reference_genomic_align->dnafrag_strand
            );

        $feature = $feature->transfer($this_slice);
	      next if (!$feature);

        $this_genomic_align_block->reference_slice($reference_slice);
        $this_genomic_align_block->reference_slice_start($feature->start + $offset - 1);
        $this_genomic_align_block->reference_slice_end($feature->end + $offset - 1);
        $this_genomic_align_block->reference_slice_strand($reference_slice->strand);
        $this_genomic_align_block->reverse_complement()
            if ($reference_slice->strand != $this_genomic_align_block->reference_genomic_align->dnafrag_strand);
        push (@$all_genomic_align_blocks, $this_genomic_align_block);
      }
    } else {
      foreach my $this_genomic_align_block (@$these_genomic_align_blocks) {
        $this_genomic_align_block->reference_slice($top_slice);
        $this_genomic_align_block->reference_slice_start(
            $this_genomic_align_block->reference_genomic_align->dnafrag_start);
        $this_genomic_align_block->reference_slice_end(
            $this_genomic_align_block->reference_genomic_align->dnafrag_end);
        $this_genomic_align_block->reference_slice_strand($reference_slice->strand);
        $this_genomic_align_block->reverse_complement()
            if ($reference_slice->strand != $this_genomic_align_block->reference_genomic_align->dnafrag_strand);
        push (@$all_genomic_align_blocks, $this_genomic_align_block);
      }
    }
  }    
  #foreach my $gab (@$all_genomic_align_blocks) {
  #    my $ref_ga = $gab->reference_genomic_align;
  #    print "ref_ga " . $ref_ga->dnafrag->name . " " . $ref_ga->dnafrag_start . " " . $ref_ga->dnafrag_end . "\n";
  #}

  
  return $all_genomic_align_blocks;
}


=head2 fetch_all_by_MethodLinkSpeciesSet_DnaFrag

  Arg  1     : Bio::EnsEMBL::Compara::MethodLinkSpeciesSet $method_link_species_set
  Arg  2     : Bio::EnsEMBL::Compara::DnaFrag $dnafrag
  Arg  3     : integer $start [optional, default = 1]
  Arg  4     : integer $end [optional, default = dnafrag_length]
  Arg  5     : integer $limit_number [optional, default = no limit]
  Arg  6     : integer $limit_index_start [optional, default = 0]
  Arg  7     : boolean $restrict_resulting_blocks [optional, default = no restriction]
  Arg  8     : boolean $view_visible [optional, default = all visible]
  Example    : my $genomic_align_blocks =
                  $genomic_align_block_adaptor->fetch_all_by_MethodLinkSpeciesSet_DnaFrag(
                      $mlss, $dnafrag, 50000000, 50250000);
  Description: Retrieve the corresponding
               Bio::EnsEMBL::Compara::GenomicAlignBlock objects.
  Returntype : ref. to an array of Bio::EnsEMBL::Compara::GenomicAlignBlock objects. Only dbID,
               adaptor and method_link_species_set are actually stored in the objects. The remaining
               attributes are only retrieved when requiered.
  Exceptions : Returns ref. to an empty array if no matching
               Bio::EnsEMBL::Compara::GenomicAlignBlock object can be retrieved
  Caller     : none
  Status     : Stable

=cut

sub fetch_all_by_MethodLinkSpeciesSet_DnaFrag {
  my ($self, $method_link_species_set, $dnafrag, $start, $end, $limit_number, $limit_index_start, $restrict, $view_visible) = @_;

  my $genomic_align_blocks = []; # returned object

  assert_ref($dnafrag, 'Bio::EnsEMBL::Compara::DnaFrag', 'dnafrag');
  my $query_dnafrag_id = $dnafrag->dbID;
  throw("[$dnafrag] has no dbID") if (!$query_dnafrag_id);

  assert_ref($method_link_species_set, 'Bio::EnsEMBL::Compara::MethodLinkSpeciesSet', 'method_link_species_set');
  throw("[$method_link_species_set] is not a Bio::EnsEMBL::Compara::MethodLinkSpeciesSet object")
      unless ($method_link_species_set and ref $method_link_species_set and
          $method_link_species_set->isa("Bio::EnsEMBL::Compara::MethodLinkSpeciesSet"));

  if ( $method_link_species_set->method->type =~ /CACTUS_HAL/ ) {
        #return $self->fetch_all_by_MethodLinkSpeciesSet_Slice( $method_link_species_set, $dnafrag->slice );

        my $ref = $dnafrag->genome_db;
        my @targets = grep { $_->dbID != $ref->dbID } @{ $method_link_species_set->species_set->genome_dbs };

        my $block_start = defined $start ? $start : $dnafrag->slice->start;
        my $block_end   = defined $end ? $end : $dnafrag->slice->end;
        return $self->_get_GenomicAlignBlocks_from_HAL( $method_link_species_set, $ref, \@targets, $dnafrag, $block_start, $block_end, $limit_number );
  }

  my $query_method_link_species_set_id = $method_link_species_set->dbID;
  throw("[$method_link_species_set] has no dbID") if (!$query_method_link_species_set_id);

  if ($limit_number) {
    return $self->_fetch_all_by_MethodLinkSpeciesSet_DnaFrag_with_limit($method_link_species_set,
        $dnafrag, $start, $end, $limit_number, $limit_index_start, $restrict);
  }
  
  $view_visible = 1 if (!defined $view_visible);

  #Create this here to pass into _create_GenomicAlign module
  my $genomic_align_adaptor = $self->db->get_GenomicAlignAdaptor;

  my $sql = qq{
          SELECT
              ga1.genomic_align_id,
              ga1.genomic_align_block_id,
              ga1.method_link_species_set_id,
              ga1.dnafrag_id,
              ga1.dnafrag_start,
              ga1.dnafrag_end,
              ga1.dnafrag_strand,
              ga1.cigar_line,
              ga1.visible,
              ga2.genomic_align_id,
              gab.score,
              gab.perc_id,
              gab.length,
              gab.group_id,
              gab.level_id
          FROM
              genomic_align ga1, genomic_align_block gab, genomic_align ga2
          WHERE 
              ga1.genomic_align_block_id = ga2.genomic_align_block_id
              AND gab.genomic_align_block_id = ga1.genomic_align_block_id
              AND ga2.method_link_species_set_id = $query_method_link_species_set_id
              AND ga2.dnafrag_id = $query_dnafrag_id 
              AND ga2.visible = $view_visible
      };
  if (defined($start) and defined($end)) {
    my $max_alignment_length = $method_link_species_set->max_alignment_length;
    my $lower_bound = $start - $max_alignment_length;
    $sql .= qq{
            AND ga2.dnafrag_start <= $end
            AND ga2.dnafrag_start >= $lower_bound
            AND ga2.dnafrag_end >= $start
        };
  }
  my $sth = $self->prepare($sql);

  $sth->execute();
  
  my $all_genomic_align_blocks;
  my $genomic_align_groups = {};
  my ($genomic_align_id, $genomic_align_block_id, $method_link_species_set_id,
      $dnafrag_id, $dnafrag_start, $dnafrag_end, $dnafrag_strand, $cigar_line, $visible,
      $query_genomic_align_id, $score, $perc_id, $length, $group_id, $level_id,);
  $sth->bind_columns(\$genomic_align_id, \$genomic_align_block_id, \$method_link_species_set_id,
      \$dnafrag_id, \$dnafrag_start, \$dnafrag_end, \$dnafrag_strand, \$cigar_line, \$visible,
      \$query_genomic_align_id, \$score, \$perc_id, \$length, \$group_id, \$level_id);
  while ($sth->fetch) {

    ## Index GenomicAlign by ga2.genomic_align_id ($query_genomic_align). All the GenomicAlign
    ##   with the same ga2.genomic_align_id correspond to the same GenomicAlignBlock.
    if (!defined($all_genomic_align_blocks->{$query_genomic_align_id})) {
      # Lazy loading of genomic_align_blocks. All remaining attributes are loaded on demand.
      $all_genomic_align_blocks->{$query_genomic_align_id} = new Bio::EnsEMBL::Compara::GenomicAlignBlock(
              -adaptor => $self,
              -dbID => $genomic_align_block_id,
              -method_link_species_set_id => $method_link_species_set_id,
              -score => $score,
              -perc_id => $perc_id,
              -length => $length,
              -group_id => $group_id,
              -reference_genomic_align_id => $query_genomic_align_id,
	      -level_id => $level_id,
          );
      push(@$genomic_align_blocks, $all_genomic_align_blocks->{$query_genomic_align_id});
    }

# # #     ## Avoids to create 1 GenomicAlignGroup object per composite segment (see below)
# # #     next if ($genomic_align_groups->{$query_genomic_align_id}->{$genomic_align_id});
    my $this_genomic_align = $self->_create_GenomicAlign($genomic_align_id,
        $genomic_align_block_id, $method_link_species_set_id, $dnafrag_id,
        $dnafrag_start, $dnafrag_end, $dnafrag_strand, $cigar_line, $visible,
	$genomic_align_adaptor);
# # #     ## Set the flag to avoid creating 1 GenomicAlignGroup object per composite segment
# # #     if ($this_genomic_align->isa("Bio::EnsEMBL::Compara::GenomicAlignGroup")) {
# # #       foreach my $this_genomic_align (@{$this_genomic_align->genomic_align_array}) {
# # #         $genomic_align_groups->{$query_genomic_align_id}->{$this_genomic_align->dbID} = 1;
# # #       }
# # #     }
    $all_genomic_align_blocks->{$query_genomic_align_id}->add_GenomicAlign($this_genomic_align);
  }

  foreach my $this_genomic_align_block (@$genomic_align_blocks) {
    my $ref_genomic_align = $this_genomic_align_block->reference_genomic_align;
    if ($ref_genomic_align->cigar_line =~ /X/) {
      # The reference GenomicAlign is part of a composite segment. We have to restrict it
      $this_genomic_align_block = $this_genomic_align_block->restrict_between_reference_positions(
          $ref_genomic_align->dnafrag_start, $ref_genomic_align->dnafrag_end, undef,
          "skip_empty_genomic_aligns");
    }
  }

  if (defined($start) and defined($end) and $restrict) {
    my $restricted_genomic_align_blocks = [];
    foreach my $this_genomic_align_block (@$genomic_align_blocks) {
      $this_genomic_align_block = $this_genomic_align_block->restrict_between_reference_positions(
          $start, $end, undef, "skip_empty_genomic_aligns");
      if (@{$this_genomic_align_block->get_all_GenomicAligns()} > 1) {
        push(@$restricted_genomic_align_blocks, $this_genomic_align_block);
      }
    }
    $genomic_align_blocks = $restricted_genomic_align_blocks;
  }

  if (!$self->lazy_loading) {
    $self->_load_DnaFrags($genomic_align_blocks);
  }

  return $genomic_align_blocks;
}


=head2 _fetch_all_by_MethodLinkSpeciesSet_DnaFrag_with_limit

  This is an internal method. Please, use the fetch_all_by_MethodLinkSpeciesSet_DnaFrag() method instead.

  Arg  1     : Bio::EnsEMBL::Compara::MethodLinkSpeciesSet $method_link_species_set
  Arg  2     : Bio::EnsEMBL::Compara::DnaFrag $dnafrag
  Arg  3     : integer $start [optional]
  Arg  4     : integer $end [optional]
  Arg  5     : integer $limit_number
  Arg  6     : integer $limit_index_start [optional, default = 0]
  Arg  7     : boolean $restrict_resulting_blocks [optional, default = no restriction]
  Example    : my $genomic_align_blocks =
                  $genomic_align_block_adaptor->_fetch_all_by_MethodLinkSpeciesSet_DnaFrag_with_limit(
                      $mlss, $dnafrag, 50000000, 50250000);
  Description: Retrieve the corresponding
               Bio::EnsEMBL::Compara::GenomicAlignBlock objects. Objects 
  Returntype : ref. to an array of Bio::EnsEMBL::Compara::GenomicAlignBlock objects. Only dbID,
               adaptor and method_link_species_set are actually stored in the objects. The remaining
               attributes are only retrieved when requiered.
  Exceptions : Returns ref. to an empty array if no matching
               Bio::EnsEMBL::Compara::GenomicAlignBlock object can be retrieved
  Caller     : fetch_all_by_MethodLinkSpeciesSet_DnaFrag
  Status     : Stable

=cut

sub _fetch_all_by_MethodLinkSpeciesSet_DnaFrag_with_limit {
  my ($self, $method_link_species_set, $dnafrag, $start, $end, $limit_number, $limit_index_start, $restrict) = @_;

  my $genomic_align_blocks = []; # returned object

  my $dnafrag_id = $dnafrag->dbID;
  my $method_link_species_set_id = $method_link_species_set->dbID;

  my $sql = qq{
          SELECT
              ga2.genomic_align_block_id,
              ga2.genomic_align_id
          FROM
              genomic_align ga2
          WHERE 
              ga2.method_link_species_set_id = $method_link_species_set_id
              AND ga2.dnafrag_id = $dnafrag_id
      };
  if (defined($start) and defined($end)) {
    my $max_alignment_length = $method_link_species_set->max_alignment_length;
    my $lower_bound = $start - $max_alignment_length;
    $sql .= qq{
            AND ga2.dnafrag_start <= $end
            AND ga2.dnafrag_start >= $lower_bound
            AND ga2.dnafrag_end >= $start
        };
  }
  $limit_index_start = 0 if (!$limit_index_start);
  $sql .= qq{ LIMIT $limit_index_start , $limit_number };

  my $sth = $self->prepare($sql);
  $sth->execute();
  
  while (my ($genomic_align_block_id, $query_genomic_align_id) = $sth->fetchrow_array) {
    # Lazy loading of genomic_align_blocks. All remaining attributes are loaded on demand.
    my $this_genomic_align_block = new Bio::EnsEMBL::Compara::GenomicAlignBlock(
            -adaptor => $self,
            -dbID => $genomic_align_block_id,
            -method_link_species_set_id => $method_link_species_set_id,
            -reference_genomic_align_id => $query_genomic_align_id,
        );
    push(@$genomic_align_blocks, $this_genomic_align_block);
  }
  if (defined($start) and defined($end) and $restrict) {
    my $restricted_genomic_align_blocks = [];
    foreach my $this_genomic_align_block (@$genomic_align_blocks) {
      $this_genomic_align_block = $this_genomic_align_block->restrict_between_reference_positions(
          $start, $end, undef, "skip_empty_genomic_aligns");
      if (@{$this_genomic_align_block->get_all_GenomicAligns()} > 1) {
        push(@$restricted_genomic_align_blocks, $this_genomic_align_block);
      }
    }
    $genomic_align_blocks = $restricted_genomic_align_blocks;
  }
  
  return $genomic_align_blocks;
}


=head2 fetch_all_by_MethodLinkSpeciesSet_DnaFrag_DnaFrag

  Arg  1     : Bio::EnsEMBL::Compara::MethodLinkSpeciesSet $method_link_species_set
  Arg  2     : Bio::EnsEMBL::Compara::DnaFrag $dnafrag (query)
  Arg  3     : integer $start [optional]
  Arg  4     : integer $end [optional]
  Arg  5     : Bio::EnsEMBL::Compara::DnaFrag $dnafrag (target)
  Arg  6     : integer $limit_number [optional]
  Arg  7     : integer $limit_index_start [optional]
  Example    : my $genomic_align_blocks =
                  $genomic_align_block_adaptor->fetch_all_by_MethodLinkSpeciesSet_DnaFrag_DnaFrag(
                      $mlss, $qy_dnafrag, 50000000, 50250000,$tg_dnafrag);
  Description: Retrieve the corresponding
               Bio::EnsEMBL::Compara::GenomicAlignBlock objects.
  Returntype : ref. to an array of Bio::EnsEMBL::Compara::GenomicAlignBlock objects.
  Exceptions : Returns ref. to an empty array if no matching
               Bio::EnsEMBL::Compara::GenomicAlignBlock object can be retrieved
  Caller     : none
  Status     : Stable

=cut

sub fetch_all_by_MethodLinkSpeciesSet_DnaFrag_DnaFrag {
  my ($self, $method_link_species_set, $dnafrag1, $start, $end, $dnafrag2, $limit_number, $limit_index_start) = @_;

  my $genomic_align_blocks = []; # returned object

  assert_ref($dnafrag1, 'Bio::EnsEMBL::Compara::DnaFrag', 'dnafrag1');
  assert_ref($dnafrag2, 'Bio::EnsEMBL::Compara::DnaFrag', 'dnafrag2');
  assert_ref($method_link_species_set, 'Bio::EnsEMBL::Compara::MethodLinkSpeciesSet', 'method_link_species_set');

  my $dnafrag_id1 = $dnafrag1->dbID;
  my $dnafrag_id2 = $dnafrag2->dbID;
  my $method_link_species_set_id = $method_link_species_set->dbID;
  throw("[$method_link_species_set_id] has no dbID") if (!$method_link_species_set_id);

  if ( $method_link_species_set->method->type eq 'CACTUS_HAL' ) {
        #return $self->fetch_all_by_MethodLinkSpeciesSet_Slice( $method_link_species_set, $dnafrag->slice );

        my $ref = $dnafrag1->genome_db;
        my @targets = ( $dnafrag2->genome_db );
        
        my $block_start = defined $start ? $start : $dnafrag1->slice->start;
        my $block_end   = defined $end ? $end : $dnafrag1->slice->end;
        return $self->_get_GenomicAlignBlocks_from_HAL( $method_link_species_set, $ref, \@targets, $dnafrag1, $block_start, $block_end, $limit_number, $dnafrag2 );
  }

  #Create this here to pass into _create_GenomicAlign module
  my $genomic_align_adaptor = $self->db->get_GenomicAlignAdaptor;

  my $sql = qq{
          SELECT
              ga1.genomic_align_id,
              ga1.genomic_align_block_id,
              ga1.method_link_species_set_id,
              ga1.dnafrag_id,
              ga1.dnafrag_start,
              ga1.dnafrag_end,
              ga1.dnafrag_strand,
              ga1.cigar_line,
              ga1.visible,
              ga2.genomic_align_id,
              ga2.genomic_align_block_id,
              ga2.method_link_species_set_id,
              ga2.dnafrag_id,
              ga2.dnafrag_start,
              ga2.dnafrag_end,
              ga2.dnafrag_strand,
              ga2.cigar_line,
              ga2.visible
          FROM
              genomic_align ga1, genomic_align ga2
          WHERE 
              ga1.genomic_align_block_id = ga2.genomic_align_block_id
              AND ga1.genomic_align_id != ga2.genomic_align_id
              AND ga2.method_link_species_set_id = $method_link_species_set_id
              AND ga1.dnafrag_id = $dnafrag_id1 AND ga2.dnafrag_id = $dnafrag_id2
      };
  if (defined($start) and defined($end)) {
    my $max_alignment_length = $method_link_species_set->max_alignment_length;
    my $lower_bound = $start - $max_alignment_length;
    $sql .= qq{
            AND ga1.dnafrag_start <= $end
            AND ga1.dnafrag_start >= $lower_bound
            AND ga1.dnafrag_end >= $start
        };
  }
  if ($limit_number && $limit_index_start) {
    $sql .= qq{ LIMIT $limit_index_start , $limit_number };
  } elsif ($limit_number) {
    $sql .= qq{ LIMIT $limit_number };
  }

  my $sth = $self->prepare($sql);
  $sth->execute();
  
  my $all_genomic_align_blocks;
  while (my ($genomic_align_id1, $genomic_align_block_id1, $method_link_species_set_id1,
             $dnafrag_id1, $dnafrag_start1, $dnafrag_end1, $dnafrag_strand1, $cigar_line1, $visible1,
             $genomic_align_id2, $genomic_align_block_id2, $method_link_species_set_id2,
             $dnafrag_id2, $dnafrag_start2, $dnafrag_end2, $dnafrag_strand2, $cigar_line2, $visible2) = $sth->fetchrow_array) {
    ## Skip if this genomic_align_block has been defined already
    next if (defined($all_genomic_align_blocks->{$genomic_align_block_id1}));
    $all_genomic_align_blocks->{$genomic_align_block_id1} = 1;
    my $gab = new Bio::EnsEMBL::Compara::GenomicAlignBlock
      (-adaptor => $self,
       -dbID => $genomic_align_block_id1,
       -method_link_species_set_id => $method_link_species_set_id1,
       -reference_genomic_align_id => $genomic_align_id1);

    # If set up, lazy loading of genomic_align
    unless ($self->lazy_loading) {
      ## Create a Bio::EnsEMBL::Compara::GenomicAlign corresponding to ga1.*
      my $this_genomic_align1 = $self->_create_GenomicAlign($genomic_align_id1,
          $genomic_align_block_id1, $method_link_species_set_id1, $dnafrag_id1,
          $dnafrag_start1, $dnafrag_end1, $dnafrag_strand1, $cigar_line1, $visible1, $genomic_align_adaptor);
      ## ... attach it to the corresponding Bio::EnsEMBL::Compara::GenomicAlignBlock
      $gab->add_GenomicAlign($this_genomic_align1);

      ## Create a Bio::EnsEMBL::Compara::GenomicAlign correponding to ga2.*
      my $this_genomic_align2 = $self->_create_GenomicAlign($genomic_align_id2,
          $genomic_align_block_id2, $method_link_species_set_id2, $dnafrag_id2,
          $dnafrag_start2, $dnafrag_end2, $dnafrag_strand2, $cigar_line2, $visible2, $genomic_align_adaptor);
      ## ... attach it to the corresponding Bio::EnsEMBL::Compara::GenomicAlignBlock
      $gab->add_GenomicAlign($this_genomic_align2);
    }
    push(@$genomic_align_blocks, $gab);
  }

  return $genomic_align_blocks;
}


=head2 retrieve_all_direct_attributes

  Arg  1     : Bio::EnsEMBL::Compara::GenomicAlignBlock $genomic_align_block
  Example    : $genomic_align_block_adaptor->retrieve_all_direct_attributes($genomic_align_block)
  Description: Retrieve the all the direct attibutes corresponding to the dbID of the
               Bio::EnsEMBL::Compara::GenomicAlignBlock object. It is used after lazy fetching
               of the object for populating it when required.
  Returntype : Bio::EnsEMBL::Compara::GenomicAlignBlock object
  Exceptions : 
  Caller     : none
  Status     : Stable

=cut

sub retrieve_all_direct_attributes {
  my ($self, $genomic_align_block) = @_;

  my $sql = qq{
          SELECT
            method_link_species_set_id,
            score,
            perc_id,
            length,
            group_id,
            level_id
          FROM
            genomic_align_block
          WHERE
            genomic_align_block_id = ?
      };

  my $sth = $self->prepare($sql);

  $sth->execute($genomic_align_block->dbID);

  my ($method_link_species_set_id, $score, $perc_id, $length, $group_id, $level_id) = $sth->fetchrow_array();
  $sth->finish();
  
  ## Populate the object
  $genomic_align_block->adaptor($self);
  $genomic_align_block->method_link_species_set_id($method_link_species_set_id)
      if (defined($method_link_species_set_id));
  $genomic_align_block->score($score) if (defined($score));
  $genomic_align_block->perc_id($perc_id) if (defined($perc_id));
  $genomic_align_block->length($length) if (defined($length));
  $genomic_align_block->group_id($group_id) if (defined($group_id));
  $genomic_align_block->level_id($level_id) if (defined($level_id));

  return $genomic_align_block;
}


=head2 store_group_id

  Arg  1     : reference to Bio::EnsEMBL::Compara::GenomicAlignBlock
  Arg  2     : group_id
  Example    : $genomic_align_block_adaptor->store_group_id($genomic_align_block, $group_id);
  Description: Method for storing the group_id for a genomic_align_block
  Returntype : 
  Exceptions : - cannot lock tables
               - cannot update GenomicAlignBlock object
  Caller     : none
  Status     : Stable

=cut

sub store_group_id {
    my ($self, $genomic_align_block, $group_id) = @_;
    
    my $sth = $self->prepare("UPDATE genomic_align_block SET group_id=? WHERE genomic_align_block_id=?;");
    $sth->execute($group_id, $genomic_align_block->dbID);
    $sth->finish();
}

=head2 lazy_loading

  [Arg  1]   : (optional)int $value
  Example    : $genomic_align_block_adaptor->lazy_loading(1);
  Description: Getter/setter for the _lazy_loading flag. This flag
               is used when fetching objects from the database. If
               the flag is OFF (default), the adaptor will fetch the
               all the attributes of the object. This is usually faster
               unless you run in some memory limitation problem. This
               happens typically when fetching loads of objects in one
               go.In this case you might want to consider using the
               lazy_loading option which return lighter objects and
               deleting objects as you use them:
               $gaba->lazy_loading(1);
               my $all_gabs = $gaba->fetch_all_by_MethodLinkSpeciesSet($mlss);
               foreach my $this_gab (@$all_gabs) {
                 # do something
                 ...
                 # delete object
                 undef($this_gab);
               }
  Returntype : integer
  Exceptions :
  Caller     : none
  Status     : Stable

=cut

sub lazy_loading {
  my ($self, $value) = @_;

  if (defined $value) {
    $self->{_lazy_loading} = $value;
  }

  return $self->{_lazy_loading};
}


=head2 _create_GenomicAlign

  [Arg  1]   : int genomic_align_id
  [Arg  2]   : int genomic_align_block_id
  [Arg  3]   : int method_link_species_set_id
  [Arg  4]   : int dnafrag_id
  [Arg  5]   : int dnafrag_start
  [Arg  6]   : int dnafrag_end
  [Arg  7]   : int dnafrag_strand
  [Arg  8]   : string cigar_line
  [Arg  9]   : int visible
  Example    : my $this_genomic_align1 = $self->_create_GenomicAlign(
                  $genomic_align_id, $genomic_align_block_id,
                  $method_link_species_set_id, $dnafrag_id,
                  $dnafrag_start, $dnafrag_end, $dnafrag_strand,
                  $cigar_line, $visible);
  Description: Creates a new Bio::EnsEMBL::Compara::GenomicAlign object
               with the values provided as arguments. If this GenomicAlign
               is part of a composite GenomicAlign, the method will return
               a Bio::EnsEMBL::Compara::GenomicAlignGroup containing all the
               underlying Bio::EnsEMBL::Compara::GenomicAlign objects instead
  Returntype : Bio::EnsEMBL::Compara::GenomicAlign object or
               Bio::EnsEMBL::Compara::GenomicAlignGroup object
  Exceptions : 
  Caller     : internal
  Status     : stable

=cut

sub _create_GenomicAlign {
  my ($self, $genomic_align_id, $genomic_align_block_id, $method_link_species_set_id,
      $dnafrag_id, $dnafrag_start, $dnafrag_end, $dnafrag_strand, $cigar_line, 
      $visible, $adaptor) = @_;

  my $new_genomic_align = Bio::EnsEMBL::Compara::GenomicAlign->new_fast
    ({'dbID' => $genomic_align_id,
      'adaptor' => $adaptor,
     'genomic_align_block_id' => $genomic_align_block_id,
     'method_link_species_set_id' => $method_link_species_set_id,
     'dnafrag_id' => $dnafrag_id,
     'dnafrag_start' => $dnafrag_start,
     'dnafrag_end' => $dnafrag_end,
     'dnafrag_strand' => $dnafrag_strand,
     'cigar_line' => $cigar_line,
     'visible' => $visible}
    );

  return $new_genomic_align;
}

=head2 _load_DnaFrags

  [Arg  1]   : listref Bio::EnsEMBL::Compara::GenomicAlignBlock objects
  Example    : $self->_load_DnaFrags($genomic_align_blocks);
  Description: Load the DnaFrags for all the GenomicAligns in these
               GenomicAlignBlock objects. This is much faster, especially
               for a large number of objects, as we fetch all the DnaFrags
               at once. Note: These DnaFrags are not cached by the
               DnaFragAdaptor at the moment
  Returntype : -none-
  Exceptions : 
  Caller     : fetch_all_* methods
  Status     : at risk

=cut

sub _load_DnaFrags {
  my ($self, $genomic_align_blocks) = @_;

  # 1. Collect all the dnafrag_ids
  my $dnafrag_ids = {};
  foreach my $this_genomic_align_block (@$genomic_align_blocks) {
    foreach my $this_genomic_align (@{$this_genomic_align_block->get_all_GenomicAligns}) {
      $dnafrag_ids->{$this_genomic_align->{dnafrag_id}} = 1;
    }
  }

  # 2. Fetch all the DnaFrags
  my %dnafrags = map {$_->{dbID}, $_}
      @{$self->db->get_DnaFragAdaptor->fetch_all_by_dbID_list([keys %$dnafrag_ids])};

  # 3. Assign the DnaFrags to the GenomicAligns
  foreach my $this_genomic_align_block (@$genomic_align_blocks) {
    foreach my $this_genomic_align (@{$this_genomic_align_block->get_all_GenomicAligns}) {
      $this_genomic_align->{'dnafrag'} = $dnafrags{$this_genomic_align->{dnafrag_id}};
    }
  }
}

=head2 _get_GenomicAlignBlocks_from_HAL

=cut

sub _get_GenomicAlignBlocks_from_HAL {
    my ($self, $mlss, $ref_gdb, $targets_gdb, $dnafrag, $start, $end, $limit, $target_dnafrag) = @_;
    my @gabs = ();

    my $dnafrag_adaptor = $mlss->adaptor->db->get_DnaFragAdaptor;
    my $genome_db_adaptor = $mlss->adaptor->db->get_GenomeDBAdaptor;

    my $map_tag = $mlss->get_value_for_tag('HAL_mapping');
    unless ( defined $map_tag ) {
        # check if there is an alternate mlss mapping to use
        my $alt_mlss_id = $mlss->get_value_for_tag('alt_hal_mlss');
        if ( defined $alt_mlss_id ) {
            $map_tag = $mlss->adaptor->fetch_by_dbID($alt_mlss_id)->get_value_for_tag('HAL_mapping');
        } else {
            my $msg = "Please define a mapping between genome_db_id and the species names from the HAL file. Example SQL:\n\n";
            $msg .= "INSERT INTO method_link_species_set_tag VALUES (<mlss_id>, \"HAL_mapping\", '{ 1 => \"hal_species1\", 22 => \"hal_species7\" }')\n\n";
            die $msg;
        }
    }
    ### HACK e86 ###
    $map_tag->{174} = 'SPRET_EiJ';
    ################

    require Bio::EnsEMBL::Compara::HAL::HALAdaptor;

    my %species_map = %{ eval $map_tag }; # read species name mapping hash from mlss_tag
    my $ref = $species_map{ $ref_gdb->dbID };

    unless ($mlss->{'_hal_adaptor'}) {
        my $hal_file = $mlss->url;  # Substitution automatically done in the MLSS object
        throw( "Path to file not found in MethodLinkSpeciesSet URL field\n" ) unless ( defined $hal_file );

        $mlss->{'_hal_adaptor'} = Bio::EnsEMBL::Compara::HAL::HALAdaptor->new($hal_file);
    }
    my $hal_fh = $mlss->{'_hal_adaptor'}->hal_filehandle;
    my $hal_seq_reg = $self->_hal_name_for_dnafrag($dnafrag, $mlss);

    my $num_targets  = scalar @$targets_gdb;
    my $id_base      = $mlss->dbID * 10000000000;
    my ($gab_id_count, $ga_id_count)  = (0, 0);
    my ($min_gab_len, $min_ga_len)    = (20, 5);

    if ( $num_targets > 1 ){ # multiple sequence alignment
      my %hal_species_map = reverse %species_map;
      my @hal_targets = map { $species_map{ $_->dbID } } @$targets_gdb;
      shift @hal_targets unless ( defined $hal_targets[0] );
      my $targets_str = join(',', @hal_targets);
      my $maf_file_str = Bio::EnsEMBL::Compara::HAL::HALAdaptor::_get_multiple_aln_blocks( $hal_fh, $targets_str, $ref, $hal_seq_reg, $start, $end );
      # my $maf_file_str = encode("utf8", $maf_file);
      # print "$maf_file_str\n\n";

      # \cJ is a special control character synonymous to \n - remove it
      # to prevent unintended newlines
      # $maf_file_str =~ s/[^A-Za-z0-9_.+-]//g;

      #my $maf_info = $self->_parse_maf( $maf_file_str );
      #exit;

      # $string =~ s/(.)/sprintf("%x",ord($1))/eg;
      # print $string;
      # print "\n\n";

      # open(OUT, '>', "mmus.copy.maf");
      # print OUT $maf_file_str;
      # close OUT;

      unless ( $maf_file_str =~ m/[A-Za-z]/ ){
        print "MAF is empty!!\n";
        return [];
      }

      # use open ':encoding(iso-8859-7)';
      open( MAF, '<', \$maf_file_str) or die "Can't open MAF file in memory";
      my @maf_lines = <MAF>;
      my $maf_info = $self->_parse_maf( \@maf_lines );
      
      for my $aln_block ( @$maf_info ) {
        my $duplicates_found = 0;
        my %species_found;
        my $block_len = $aln_block->[0]->{length};

        next if ( $block_len <= $min_gab_len );

        my $gab = new Bio::EnsEMBL::Compara::GenomicAlignBlock(
          -length => $block_len,
          -method_link_species_set => $mlss,
          -adaptor => $mlss->adaptor->db->get_GenomicAlignBlockAdaptor,
          -dbID => $id_base + $gab_id_count,
        );
        $gab_id_count++;

        my $ga_adaptor = $mlss->adaptor->db->get_GenomicAlignAdaptor;
        my (@genomic_align_array, $ref_genomic_align);
        foreach my $seq (@$aln_block) {
          # find dnafrag for the region
          my ( $species_id, $chr ) = split(/\./, $seq->{display_id});
          next if ( $chr =~ m/scaffold/ );
          my $this_gdb = $genome_db_adaptor->fetch_by_dbID( $hal_species_map{$species_id} );
          my $this_dnafrag = $dnafrag_adaptor->fetch_by_GenomeDB_and_synonym($this_gdb, $chr);
          unless ( defined $this_dnafrag ) {
            next;
          }
          # when fetching by slice, input slice will be set as $dnafrag->slice, complete with start and end positions
          # this can mess up subslicing down the line - reset it and it will be pulled fresh from the db
          $this_dnafrag->{'_slice'} = undef; 

          if ( $this_dnafrag->length < $seq->{end} ) {
            $self->warning('Ommitting ' . $this_gdb->name . ' from GenomicAlignBlock. Alignment position does not fall within the length of the chromosome');
            next;
          }

          # check length of genomic align meets threshold
          next if ( abs( $seq->{start} - $seq->{end} ) + 1 < $min_ga_len );

          if ( !$duplicates_found ){
            my $species_name = $this_dnafrag->genome_db->name;
            if ( $species_found{$species_name} ){
                $duplicates_found = 1;
            } else {
                $species_found{$species_name} = 1;
            }
          }
          

          # create cigar line
          my $this_cigar = Bio::EnsEMBL::Compara::Utils::Cigars::cigar_from_alignment_string($seq->{seq});

          my $genomic_align = new Bio::EnsEMBL::Compara::GenomicAlign(
            -genomic_align_block => $gab,
            -aligned_sequence => $seq->{seq}, 
            -dnafrag => $this_dnafrag, 
            -dnafrag_start => $seq->{start},
            -dnafrag_end => $seq->{end},
            -dnafrag_strand => $seq->{strand},
            -cigar_line => $this_cigar, 
            -dbID => $id_base + $ga_id_count,
            -visible => 1,
            -adaptor => $ga_adaptor,
          );
          $genomic_align->cigar_line($this_cigar);
          $genomic_align->aligned_sequence( $seq->{seq} );
          $genomic_align->genomic_align_block( $gab );
          $genomic_align->dbID( $id_base + $ga_id_count );
          push( @genomic_align_array, $genomic_align );
          $ref_genomic_align = $genomic_align if ( $this_gdb->dbID == $ref_gdb->dbID );
          $ga_id_count++;
        }

        next if ( scalar(@genomic_align_array) < 2 );

        $gab->genomic_align_array(\@genomic_align_array);
        next unless ( defined $ref_genomic_align );
        $gab->reference_genomic_align($ref_genomic_align);

        # check for duplicate species
        if ( $duplicates_found ) {
            my $split_gabs = $self->_split_genomic_aligns( $gab, $min_gab_len );
            my $gab_adaptor = $mlss->adaptor->db->get_GenomicAlignBlockAdaptor;

            foreach my $this_gab ( @$split_gabs ) {
                $this_gab->adaptor($gab_adaptor);
                $this_gab->dbID($id_base + $gab_id_count);

                push( @gabs, $this_gab );
                $gab_id_count++;
            }
        } else {
            push(@gabs, $gab);
        }

      }
      close MAF;
    }

    else { # pairwise alignment
      my $ref_slice_adaptor = $ref_gdb->db_adaptor->get_SliceAdaptor;

      foreach my $target_gdb (@$targets_gdb) {
          my $nonref_slice_adaptor = $target_gdb->db_adaptor->get_SliceAdaptor;
          my $target = $species_map{ $target_gdb->dbID };

          # print "hal_file is $hal_file\n";
          # print "ref is $ref\n";
          # print "target is $target\n";
          # print "seq_region is $hal_seq_reg\n";
          # print "target_seq_region is ".$target_dnafrag->name."\n" if (defined $target_dnafrag);
          # print "start is $start\n";
          # print "end is $end\n";

          my @blocks;
          if ( $target_dnafrag ){
              my $t_hal_seq_reg = $self->_hal_name_for_dnafrag($target_dnafrag, $mlss);
              @blocks = Bio::EnsEMBL::Compara::HAL::HALAdaptor::_get_pairwise_blocks_filtered($hal_fh, $target, $ref, $hal_seq_reg, $start, $end, $t_hal_seq_reg);
          }
          else {
              @blocks = Bio::EnsEMBL::Compara::HAL::HALAdaptor::_get_pairwise_blocks($hal_fh, $target, $ref, $hal_seq_reg, $start, $end);
          }
          
          foreach my $entry (@blocks) {
  	        if (defined $entry) {
              next if (@$entry[3] < $min_gab_len ); # skip blocks shorter than 20bp

              my $gab = new Bio::EnsEMBL::Compara::GenomicAlignBlock(
                  -length => @$entry[3],
                  -method_link_species_set => $mlss,
                  -adaptor => $mlss->adaptor->db->get_GenomicAlignBlockAdaptor,
                  -dbID => $id_base + $gab_id_count,
              );
              $gab_id_count++;
  		
              my $ga_adaptor = $mlss->adaptor->db->get_GenomicAlignAdaptor;
  		        # Create cigar strings
  		        my ($ref_aln_seq, $target_aln_seq) = ( $entry->[6], $entry->[5] );
  		        my $ref_cigar = Bio::EnsEMBL::Compara::Utils::Cigars::cigar_from_alignment_string($ref_aln_seq);
  		        my $target_cigar = Bio::EnsEMBL::Compara::Utils::Cigars::cigar_from_alignment_string($target_aln_seq);

              my $target_dnafrag = $dnafrag_adaptor->fetch_by_GenomeDB_and_synonym($target_gdb, @$entry[0]);
              $target_dnafrag->{'_slice'} = undef;
              next unless ( defined $target_dnafrag );
              
              # check that alignment falls within requested range
              next if ( @$entry[2] + @$entry[3] > $end || @$entry[1] + @$entry[3] > $end );

              # check length of genomic align meets threshold
              next if ( @$entry[3] < $min_ga_len );

              my $genomic_align = new Bio::EnsEMBL::Compara::GenomicAlign(
                  -genomic_align_block => $gab,
                  -aligned_sequence => $target_aln_seq, #@$entry[5],
                  -dnafrag => $target_dnafrag,
                  -dnafrag_start => @$entry[2] + 1,
                  -dnafrag_end => @$entry[2] + @$entry[3],
                  -dnafrag_strand => @$entry[4] eq '+' ? 1 : -1,
                  -cigar_line => $target_cigar,
                  -dbID => $id_base + $ga_id_count,
                  -visible => 1,
                  -adaptor => $ga_adaptor,
  	          );
              $genomic_align->cigar_line($target_cigar);
              $genomic_align->aligned_sequence( $target_aln_seq );
              $genomic_align->genomic_align_block( $gab );
              $genomic_align->dbID( $id_base + $ga_id_count );
              $ga_id_count+=1;

              $dnafrag->{'_slice'} = undef;
              my $ref_genomic_align = new Bio::EnsEMBL::Compara::GenomicAlign(
                -genomic_align_block => $gab,
                -aligned_sequence => $ref_aln_seq, #@$entry[6],
                -dnafrag => $dnafrag,
                -dnafrag_start => @$entry[1] + 1,
                -dnafrag_end => @$entry[1] + @$entry[3],
                -dnafrag_strand => @$entry[4] eq '+' ? 1 : -1,
                -cigar_line => $ref_cigar,
                -dbID => $id_base + $ga_id_count,
                -visible => 1,
                -adaptor => $ga_adaptor,
  		        );
              $ref_genomic_align->cigar_line($ref_cigar);
              $ref_genomic_align->aligned_sequence( $ref_aln_seq );
              $ref_genomic_align->genomic_align_block( $gab );
              $ref_genomic_align->dbID( $id_base + $ga_id_count );
              $ga_id_count++;

  		      $gab->genomic_align_array([$ref_genomic_align, $genomic_align]);
              $gab->reference_genomic_align($ref_genomic_align);
              push(@gabs, $gab);
            }
            last if ( $limit && scalar(@gabs) >= $limit );
          }
      }
    }

    return \@gabs;
}

sub _split_genomic_aligns {
    my ( $self, $gab, $min_gab_len ) = @_;
    my @ga_array = @{ $gab->genomic_align_array };

    my @cigar_lines       = map { $_->cigar_line } @ga_array;
    my $ref_genomic_align = shift @ga_array;
    my $ref_cigar         = shift @cigar_lines;

    my @non_matching_cigars = grep { $_ ne $ref_cigar } @cigar_lines;
    my @m_end = grep { $_ =~ m/M$/ } @non_matching_cigars;
    my @d_end = grep { $_ =~ m/D$/ } @non_matching_cigars;

    my $max_end_match = 0;
    foreach my $end_match ( @d_end ){
        $end_match =~ m/(\d+)D$/;
        $max_end_match = $1 if ( $1 > $max_end_match );
    }

    # check whether we can split the block in half(ish) or whether it's
    # better to keep the main block intact and move the offending genomic_aligns
    # to a new block
    my ($can_split, $trim) = (1, 0);
    foreach my $end_gap ( @d_end ) {
        # if it also starts with a deletion, then the match is surrounded on each
        # side and we can't just split the block down the middle. If the deletion
        # is shorter than the matched region, we should just trim it off (we lose
        # less data this way) and split in two as usual
        if ( $end_gap =~ m/^(\d*)D(\d*)M/ ) {
            my $d = $1 eq '' ? 1 : $1;
            my $m = $2 eq '' ? 1 : $2;
            if ( $d < $m ) {
                $trim = $d if ( $d > $trim );
            } else {
                $can_split = 0;
                last;
            }
        }
        $end_gap =~ m/(\d+)D$/;
        if ( $1 < $max_end_match ){
            $can_split = 0;
        }
    }

    if ( $trim > 0) {
        my $new_gab = $gab->restrict_between_alignment_positions($trim+1, $gab->length, 1 );
        $gab = $new_gab;
        $can_split = 1;
    }

    my @split_blocks = ();
    if ( $can_split ){ # restrict the block to create 2, non-overlapping ones
        my $aln_length = $gab->length;
        my $split_pos  = ($aln_length - $max_end_match);

        if ( $split_pos > $min_gab_len ) {
            my $block1 = $gab->restrict_between_alignment_positions(1, $split_pos, 1 );
            push( @split_blocks, $block1 );
        }

        if ( $max_end_match > $min_gab_len ) {
            my $block2 = $gab->restrict_between_alignment_positions($split_pos+1, $aln_length, 1 );
            push( @split_blocks, $block2 );
        }
    } else { # keep main block, but remove offending duplications
        # find duplicated species
        my %counts;
        for my $ga ( @ga_array ) {
            $counts{ $ga->genome_db->name }++;
        }

        my @pruned_ga_array;
        for my $species ( keys %counts ) {
            if ( $counts{$species} > 1 ) {
                my @species_gas = grep { $_->genome_db->name eq $species } @ga_array;
                my $longest_genomic_align = shift @species_gas;
                for my $this_genomic_align ( @species_gas ){
                    $longest_genomic_align = $this_genomic_align if ( length($this_genomic_align->original_sequence) > length($longest_genomic_align->original_sequence) );
                }
                push(@pruned_ga_array, $longest_genomic_align);
            } else {
                for my $g ( @ga_array ) {
                    if ( $g->genome_db->name eq $species ){
                        push( @pruned_ga_array, $g );
                        last;
                    }
                }
            }
        }
        $gab->genomic_align_array( \@pruned_ga_array );
    }

    return \@split_blocks;
}

sub _hal_name_for_dnafrag {
    my ( $self, $dnafrag, $mlss ) = @_;

    my $genome_db_id = $dnafrag->genome_db_id;
    my $seq_reg = $dnafrag->name;

    # first check if there are overriding synonyms in the mlss_tag table
    my $alt_syn_tag = $mlss->get_value_for_tag('alt_synonyms');
    if ( defined $alt_syn_tag ) {
        my %alt_synonyms = %{ eval $alt_syn_tag };
        return $alt_synonyms{$genome_db_id}->{$seq_reg} if ( defined $alt_synonyms{$genome_db_id}->{$seq_reg} );
    }

    # next, check if an alt_hal_mlss has been defined
    my $alt_mlss_id = $mlss->get_value_for_tag('alt_hal_mlss');
    if ( defined $alt_mlss_id ) {
        $alt_syn_tag = $mlss->adaptor->fetch_by_dbID($alt_mlss_id)->get_value_for_tag('alt_synonyms');
        my %alt_synonyms = %{ eval $alt_syn_tag };
        return $alt_synonyms{$genome_db_id}->{$seq_reg} if ( defined $alt_synonyms{$genome_db_id}->{$seq_reg} );
    }

    my @external_dbs = ( 'UCSC', 'GenBank', 'INSDC' );

    my @syns;
    for my $ex_db ( @external_dbs ){
        @syns = @{ $dnafrag->slice->get_all_synonyms($ex_db) };
        return $syns[0]->name if ( defined $syns[0] );
    }
    return "chr$seq_reg";
}


sub _parse_maf {
  my ($self, $maf_lines) = @_;

  my @blocks;
  my $x = 0;
  for my $line ( @$maf_lines ) {
    chomp $line;
    push( @blocks, [] ) if ( $line =~ m/^a/ );

    if ( $line =~ m/^s/ ) {
      my %this_seq;
      my @spl = split( /\s+/, $line );
      $this_seq{display_id} = $spl[1];
      $this_seq{start}      = $spl[2];
      $this_seq{length}     = $spl[3];
      $this_seq{strand}     = ($spl[4] eq '+') ? 1 : -1;
      $this_seq{end}        = $spl[2] + $spl[3];
      $this_seq{seq}        = $spl[6];
      push( @{ $blocks[-1] }, \%this_seq );
    }
  }

  return \@blocks;
}

1;
