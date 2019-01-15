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

=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

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

=head1 DESCRIPTION

This modules contains common methods used when dealing with the
Compara master database. They can in fact be called on other
databases too.

- update_dnafrags: updates the DnaFrags of a species

=head1 METHODS

=cut

package Bio::EnsEMBL::Compara::Utils::MasterDatabase;

use strict;
use warnings;
use Bio::EnsEMBL::Utils::Exception qw(throw warning verbose);
use Bio::EnsEMBL::Utils::Argument qw(rearrange);

use Bio::EnsEMBL::Compara::Method;
use Bio::EnsEMBL::Compara::MethodLinkSpeciesSet;

use Data::Dumper;
$Data::Dumper::Maxdepth=3;


=head2 update_dnafrags

  Arg[1]      : Bio::EnsEMBL::Compara::DBSQL::DBAdaptor $compara_dba
  Arg[2]      : Bio::EnsEMBL::Compara::GenomeDB $genome_db
  Arg[3]      : Bio::EnsEMBL::DBSQL::DBAdaptor $species_dba
  Arg[4]      : (optional) Boolean $only_non_reference
  Description : This method fetches all the dnafrag in the compara DB
                corresponding to the $genome_db. It also gets the list
                of top_level seq_regions from the species core DB and
                updates the list of dnafrags in the compara DB.
                If $only_non_reference is set, the method will only
                consider the non-refrence dnafrags / slices.
  Returns     : Number of new DnaFrags
  Exceptions  : -none-

=cut

sub update_dnafrags {
    my ($compara_dba, $genome_db, $species_dba, $only_non_reference) = @_;

    $species_dba //= $genome_db->db_adaptor;
    my $dnafrag_adaptor = $compara_dba->get_adaptor('DnaFrag');
    my $old_dnafrags = $dnafrag_adaptor->fetch_all_by_GenomeDB($genome_db);
    my $old_dnafrags_by_name;
    foreach my $old_dnafrag (@$old_dnafrags) {
        next if $only_non_reference && $old_dnafrag->is_reference;
        $old_dnafrags_by_name->{$old_dnafrag->name} = $old_dnafrag;
    }

    my $gdb_slices = $genome_db->genome_component
        ? $species_dba->get_SliceAdaptor->fetch_all_by_genome_component($genome_db->genome_component)
        : $species_dba->get_SliceAdaptor->fetch_all('toplevel', undef, 1, 1, 1);
    die 'Could not fetch any toplevel slices from '.$genome_db->name() unless(scalar(@$gdb_slices));

    my $new_dnafrags_ids = 0;
    my $existing_dnafrags_ids = 0;
    my @species_overall_len;#rule_2
    foreach my $slice (@$gdb_slices) {
        next if $only_non_reference && $slice->is_reference;

        my $new_dnafrag = Bio::EnsEMBL::Compara::DnaFrag->new_from_Slice($slice, $genome_db);

        push( @species_overall_len, $new_dnafrag->length()) if $new_dnafrag->is_reference;#rule_2

        if (my $old_df = delete $old_dnafrags_by_name->{$slice->seq_region_name}) {
            $new_dnafrag->dbID($old_df->dbID);
            $dnafrag_adaptor->update($new_dnafrag);
            $existing_dnafrags_ids++;

        } else {
            $dnafrag_adaptor->store($new_dnafrag);
            $new_dnafrags_ids++;
        }
    }

    #-------------------------------------------------------------------------------
    my $top_limit;
    if ( scalar(@species_overall_len) < 50 ) {
        $top_limit = scalar(@species_overall_len) - 1;
    }
    else {
        $top_limit = 49;
    }

    my @top_frags = ( sort { $b <=> $a } @species_overall_len )[ 0 .. $top_limit ];
    my @low_limit_frags = ( sort { $b <=> $a } @species_overall_len )[ ( $top_limit + 1 ) .. scalar(@species_overall_len) - 1 ];
    my $avg_top = _mean(@top_frags);

    my $ratio_top_highest = _sum(@top_frags)/_sum(@species_overall_len);

    #we set to 1 in case there are no values since we want to still compute the log
    my $avg_low;
    my $ratio_top_low;
    if ( scalar(@low_limit_frags) == 0 ) {

        #$ratio_top_low = 1;
        $avg_low = 1;
    }
    else {
        $avg_low = _mean(@low_limit_frags);
    }

    $ratio_top_low = $avg_top/$avg_low;

    my $log_ratio_top_low = log($ratio_top_low)/log(10);#rule_4

    undef @top_frags;
    undef @low_limit_frags;
    undef @species_overall_len;

    #After initially considering taking all the genomes that match cov >= 65% || log >= 3
    #We then decided to combine both variables and take all the genomes for
    #which log >= 10 - 3 * cov/25%. In other words, the classifier is a line that
    #passes by the (50%,4) and (75%,1) points. It excludes genomes that have a log
    #value >= 3 but a poor coverage, or a decent coverage but a low log value.
    #my $is_good_for_alignment = ($ratio_top_highest > 0.68) || ( $log_ratio_top_low > 3 ) ? 1 : 0;

    my $diagonal_cutoff = 10-3*($ratio_top_highest/0.25);

    my $is_good_for_alignment = ($log_ratio_top_low > $diagonal_cutoff) ? 1 : 0;

    my $sth = $compara_dba->dbc->prepare("UPDATE genome_db SET is_good_for_alignment = ? WHERE name = ? AND assembly = ?");
    $sth->execute($is_good_for_alignment,$genome_db->name(),$genome_db->assembly);
    $sth->finish;

    #-------------------------------------------------------------------------------

    print "$existing_dnafrags_ids DnaFrags already in the database. Inserted $new_dnafrags_ids new DnaFrags.\n";

    if (keys %$old_dnafrags_by_name) {
        print 'Now deleting ', scalar(keys %$old_dnafrags_by_name), ' former DnaFrags...';
        my $sth = $compara_dba->dbc->prepare('DELETE FROM dnafrag WHERE dnafrag_id = ?');
        foreach my $deprecated_dnafrag (values %$old_dnafrags_by_name) {
            $sth->execute($deprecated_dnafrag->dbID);
        }
        print "  ok!\n\n";
    }
    return $new_dnafrags_ids;
}


############################################################
#                 update_genome.pl methods                 #
############################################################

=head2 update_genome

  Arg[1]      : string $species_name
  Arg[2]      : Bio::EnsEMBL::Compara::DBSQL::DBAdaptor $compara_dba
  Arg[3]      : (optional) boolean $release
  Arg[4]      : (optional) boolean $force
  Arg[5]      : (optional) int $taxon_id
  Arg[6]      : (optional) int $offset
  Description : Does everything for this species: create / update the GenomeDB entry, and load the DnaFrags.
  				To set the new species as current, set $release = 1. If the GenomeDB already exists, set $force = 1 
  				to force the update of DnaFrags. Use $taxon_id to manually set the taxon id for this species (default
  				is to find it in the core db). $offset can be used to override autoincrement of dbID
  Returns     : arrayref containing (1) new Bio::EnsEMBL::Compara::GenomeDB object, (2) arrayref of updated 
                component GenomeDBs, (3) number of dnafrags updated
  Exceptions  : none

=cut

sub update_genome {
    # my ($compara_dba, $species, $release, $force, $taxon_id, $offset) = @_;
    my $compara_dba = shift;
    my $species = shift;

    my($release, $force, $taxon_id, $offset) = rearrange([qw(RELEASE FORCE TAXON_ID OFFSET)], @_);

    my $species_no_underscores = $species;
    $species_no_underscores =~ s/\_/\ /;

    my $species_db = Bio::EnsEMBL::Registry->get_DBAdaptor($species, "core");
    if(! $species_db) {
        $species_db = Bio::EnsEMBL::Registry->get_DBAdaptor($species_no_underscores, "core");
    }
    throw ("Cannot connect to database [${species_no_underscores} or ${species}]") if (!$species_db);

    my ( $new_genome_db, $component_genome_dbs, $new_dnafrags );
    my $gdbs = $compara_dba->dbc->sql_helper->transaction( -CALLBACK => sub {
        $new_genome_db = _update_genome_db($species_db, $compara_dba, $release, $force, $taxon_id, $offset);
        print "GenomeDB after update: ", $new_genome_db->toString, "\n\n";
        print "Fetching DnaFrags from " . $species_db->dbc->host . "/" . $species_db->dbc->dbname . "\n";
        $new_dnafrags = update_dnafrags($compara_dba, $new_genome_db, $species_db);
        $component_genome_dbs = _update_component_genome_dbs($new_genome_db, $species_db, $compara_dba);
        foreach my $component_gdb (@$component_genome_dbs) {
            $new_dnafrags += update_dnafrags($compara_dba, $component_gdb, $species_db);
        }
        print_method_link_species_sets_to_update_by_genome_db($compara_dba, $new_genome_db);
        # return [$new_genome_db, $component_genome_dbs, $new_dnafrags];
    } );
    $species_db->dbc()->disconnect_if_idle();
    return [$new_genome_db, $component_genome_dbs, $new_dnafrags];
}


=head2 _update_genome_db

  Arg[1]      : Bio::EnsEMBL::DBSQL::DBAdaptor $species_dba
  Arg[2]      : Bio::EnsEMBL::Compara::DBSQL::DBAdaptor $compara_dba
  Arg[3]      : (optional) boolean $release
  Arg[4]      : (optional) boolean $force
  Arg[5]      : (optional) int $taxon_id
  Arg[6]      : (optional) int $offset
  Description : This method takes all the information needed from the
                species database in order to update the genome_db table
                of the compara database
  Returns     : The new Bio::EnsEMBL::Compara::GenomeDB object
  Exceptions  : throw if the genome_db table is up-to-date unless the
                --force option has been activated

=cut

sub _update_genome_db {
  my ($species_dba, $compara_dba, $release, $force, $taxon_id, $offset) = @_;

  my $genome_db_adaptor = $compara_dba->get_GenomeDBAdaptor();
  my $genome_db = eval {$genome_db_adaptor->fetch_by_core_DBAdaptor($species_dba)};

  if ($genome_db and $genome_db->dbID) {
    if (not $force) {
      my $species_production_name = $genome_db->name;
      my $this_assembly = $genome_db->assembly;
      throw "\n\n** GenomeDB with this name [$species_production_name] and assembly".
        " [$this_assembly] is already in the compara DB **\n".
        "** You can use the --force option IF YOU REALLY KNOW WHAT YOU ARE DOING!! **\n\n";
    }
  }

  if ($genome_db) {
    print "GenomeDB before update: ", $genome_db->toString, "\n";

    # Get fresher information from the core database
    $genome_db->db_adaptor($species_dba, 1);
    $genome_db->last_release(undef);

    # And store it back in Compara
    $genome_db_adaptor->update($genome_db);
  } else { # new genome or new assembly!!
    $genome_db = Bio::EnsEMBL::Compara::GenomeDB->new_from_DBAdaptor($species_dba);
    $genome_db->taxon_id( $taxon_id ) if $taxon_id;

    if (!defined($genome_db->name)) {
      throw "Cannot find species.production_name in meta table for ".($species_dba->locator).".\n";
    }
    if (!defined($genome_db->taxon_id)) {
      throw "Cannot find species.taxonomy_id in meta table for ".($species_dba->locator).".\n".
          "   You can use the --taxon_id option";
    }
    print "New GenomeDB for Compara: ", $genome_db->toString, "\n";

    # new ID search if $offset is true
    if($offset) {
        my ($max_id) = $compara_dba->dbc->db_handle->selectrow_array('select max(genome_db_id) from genome_db where genome_db_id > ?', undef, $offset);
    	$max_id = $offset unless $max_id;
	    $genome_db->dbID($max_id + 1);
    }
    $genome_db_adaptor->store($genome_db);
  }

  $genome_db_adaptor->make_object_current($genome_db) if $release;
  return $genome_db;
}


=head2 _update_component_genome_dbs

  Description : Updates all the genome components (only for polyploid genomes)
  Returns     : -none-
  Exceptions  : none

=cut

sub _update_component_genome_dbs {
    my ($principal_genome_db, $species_dba, $compara_dba) = @_;

    my @gdbs;
    my $genome_db_adaptor = $compara_dba->get_GenomeDBAdaptor();
    foreach my $c (@{$species_dba->get_GenomeContainer->get_genome_components}) {
        my $copy_genome_db = $principal_genome_db->make_component_copy($c);
        $genome_db_adaptor->store($copy_genome_db);
        push @gdbs, $copy_genome_db;
        print "Component '$c' genome_db:\n\t", $copy_genome_db->toString(), "\n";
    }
    return \@gdbs;
}

=head2 print_method_link_species_sets_to_update_by_genome_db

  Arg[1]      : Bio::EnsEMBL::Compara::DBSQL::DBAdaptor $compara_dba
  Arg[2]      : Bio::EnsEMBL::Compara::GenomeDB $genome_db
  Description : This method prints all the genomic MethodLinkSpeciesSet
                that need to be updated (those which correspond to the
                $genome_db).
                NB: Only method_link with a dbID<200 || dbID>=500 are taken into
                account (they should be the genomic ones)
  Returns     : -none-
  Exceptions  :

=cut

sub print_method_link_species_sets_to_update_by_genome_db {
  my ($compara_dba, $genome_db, $release) = @_;

  my $method_link_species_set_adaptor = $compara_dba->get_adaptor("MethodLinkSpeciesSet");
  my $genome_db_adaptor = $compara_dba->get_adaptor("GenomeDB");

  my @these_gdbs;


  my $method_link_species_sets;
  my $mlss_found = 0;
  # foreach my $this_genome_db (@{$genome_db_adaptor->fetch_all()}) {
  #   next if ($this_genome_db->name ne $genome_db->name);
  my $this_genome_db = _prev_genome_db($compara_dba, $genome_db);
  return unless $this_genome_db;
    foreach my $this_method_link_species_set (@{$method_link_species_set_adaptor->fetch_all_by_GenomeDB($this_genome_db)}) {
      next unless $this_method_link_species_set->is_current || $release;
      $mlss_found = 1;
      $method_link_species_sets->{$this_method_link_species_set->method->dbID}->
          {join("-", sort map {$_->name} @{$this_method_link_species_set->species_set->genome_dbs})} = $this_method_link_species_set;
    }
  # }

  return unless $mlss_found;

  print "List of Bio::EnsEMBL::Compara::MethodLinkSpeciesSet to update:\n" if ! $release;
  print "List of Bio::EnsEMBL::Compara::MethodLinkSpeciesSet retired:\n" if $release;
  foreach my $this_method_link_id (sort {$a <=> $b} keys %$method_link_species_sets) {
    next if ($this_method_link_id > 200) and ($this_method_link_id < 500); # Avoid non-genomic method_link_species_set
    foreach my $this_method_link_species_set (values %{$method_link_species_sets->{$this_method_link_id}}) {
      printf "%8d: ", $this_method_link_species_set->dbID,;
      print $this_method_link_species_set->method->type, " (", $this_method_link_species_set->name, ")\n";
    }
  }

}

=head2 _prev_genome_db

	Arg[1]      : Bio::EnsEMBL::Compara::DBSQL::DBAdaptor $compara_dba
	Arg[2]      : Bio::EnsEMBL::Compara::GenomeDB $gdb
	Description : Find the GenomeDB object that $gdb has succeeded
	Returns     : Bio::EnsEMBL::Compara::GenomeDB

=cut

sub _prev_genome_db {
    my ($compara_dba, $gdb) = @_;

    my $genome_db_adaptor = $compara_dba->get_adaptor("GenomeDB");

    my $prev_gdb;
    my @this_species_gdbs = sort { $a->first_release <=> $b->first_release } grep { $_->name eq $gdb->name && $_->dbID != $gdb->dbID && defined $gdb->first_release } @{$genome_db_adaptor->fetch_all()};
    return undef unless scalar @this_species_gdbs >= 1;
    return pop @this_species_gdbs;
}


############################################################
#                edit_collection.pl methods                #
############################################################

=head2 new_collection

	Arg[1]      : Bio::EnsEMBL::Compara::DBSQL::DBAdaptor $compara_dba
	Arg[2]      : string $collection_name
	Arg[3]      : arrayref $species_names
	Arg[4]      : boolean $dry_run
	Description : Create a new collection species set from the given list of species
	              names (most recent assemblies). To perform the operation WITHOUT
	              storing to the database, set $dry_run = 1
	Returns     : Bio::EnsEMBL::Compara::SpeciesSet

=cut

sub new_collection {
    # my ( $compara_dba, $collection_name, $species_names, $dry_run ) = @_;
    my $compara_dba = shift;
    my $collection_name = shift;
    my $species_names = shift;
    my($release, $dry_run, $incl_components) = rearrange([qw(RELEASE DRY_RUN INCL_COMPONENTS)], @_);


    my $ss_adaptor = $compara_dba->get_SpeciesSetAdaptor;
    my $collection_ss;

    my $genome_db_adaptor = $compara_dba->get_GenomeDBAdaptor;
    my @new_collection_gdbs = map {$genome_db_adaptor->_find_most_recent_by_name($_)} @$species_names;
    @new_collection_gdbs = _expand_components(\@new_collection_gdbs) if $incl_components;

    my $new_collection_ss;
    $compara_dba->dbc->sql_helper->transaction( -CALLBACK => sub {
        $new_collection_ss = $ss_adaptor->update_collection($collection_name, \@new_collection_gdbs, $release);
        die "\n\n*** Dry-run mode requested. No changes were made to the database ***\n\nThe following collection WOULD have been created:\n" . $new_collection_ss->toString . "\n\n" if $dry_run;
        print "\nStored: " . $new_collection_ss->toString . "\n\n";
    } );

    return $new_collection_ss;
}

=head2 update_collection

	Arg[1]      : Bio::EnsEMBL::Compara::DBSQL::DBAdaptor $compara_dba
	Arg[2]      : string $collection_name
	Arg[3]      : arrayref $species_names
	Arg[4]      : boolean $dry_run
	Description : Create a new collection species set from the given list of species
	              names (most recent assemblies). To perform the operation WITHOUT
	              storing to the database, set $dry_run = 1
	Returns     : Bio::EnsEMBL::Compara::SpeciesSet

=cut

sub update_collection {
    # my ( $compara_dba, $collection_name, $species_names ) = @_;
    my $compara_dba = shift;
    my $collection_name = shift;
    my $species_names = shift;
    my($release, $dry_run, $incl_components) = rearrange([qw(RELEASE DRY_RUN INCL_COMPONENTS)], @_);

    my $ss_adaptor = $compara_dba->get_SpeciesSetAdaptor;
    my $collection_ss;

    my $genome_db_adaptor = $compara_dba->get_GenomeDBAdaptor;
    my @requested_species_gdbs = map {$genome_db_adaptor->_find_most_recent_by_name($_)} @$species_names;

    my @new_collection_gdbs = @requested_species_gdbs;
    $collection_ss = $ss_adaptor->fetch_collection_by_name($collection_name);
    warn "Adding species to collection '$collection_name' (dbID: " . $collection_ss->dbID . ")\n";

    my @gdbs_in_current_collection = @{$collection_ss->genome_dbs};
    my %collection_species_by_name = (map {$_->name => $_} @gdbs_in_current_collection);

    foreach my $coll_gdb ( @gdbs_in_current_collection ) {
        # if this species already exists in the collection, skip it as we've already added the newest assembly
        my $name_match_gdb = grep { $coll_gdb->name eq $_->name } @requested_species_gdbs;
        next if $name_match_gdb == 1;

        if ( $name_match_gdb ) {
        	print Dumper $name_match_gdb;
            warn "Replaced " . $coll_gdb->name . " assembly " . $coll_gdb->assembly . " with " . $name_match_gdb->assembly . "\n";
        } else {
            push( @new_collection_gdbs, $coll_gdb );
        }
    }
    @new_collection_gdbs = _expand_components(\@new_collection_gdbs) if $incl_components;

    my $new_collection_ss;
    $compara_dba->dbc->sql_helper->transaction( -CALLBACK => sub {
        $new_collection_ss = $ss_adaptor->update_collection($collection_name, \@new_collection_gdbs, $release);

        print_method_link_species_sets_to_update_by_collection($compara_dba, $collection_ss);
        die "\n\n*** Dry-run mode requested. No changes were made to the database ***\n\nThe following collection WOULD have been created:\n" . $new_collection_ss->toString . "\n\n" if $dry_run;
        print "\nStored: " . $new_collection_ss->toString . "\n\n";
    } );

    return $new_collection_ss;
}


=head2 _expand_components

  Arg[1]      : Arrayref of GenomeDBs
  Description : expand a list of GenomeDBs to include the component GenomeDBs
  Returns     : Array of GenomeDBs (same as input if no polyploid genomes are passed)

=cut

sub _expand_components {
    my $genome_dbs = shift;
    my @expanded_gdbs;
    foreach my $gdb ( @$genome_dbs ) {
        push @expanded_gdbs, $gdb;
        my $components = $gdb->component_genome_dbs;
        push @expanded_gdbs, @$components if scalar @$components > 0;
    }
    return @expanded_gdbs;
}

=head2 print_method_link_species_sets_to_update_by_collection

  Arg[1]      : Bio::EnsEMBL::Compara::DBSQL::DBAdaptor $compara_dba
  Arg[2]      : Bio::EnsEMBL::Compara::SpeciesSet $collection_ss
  Description : This method prints all the genomic MethodLinkSpeciesSet
                that need to be updated (those which correspond to the
                $collection_ss species-set).
  Returns     : -none-
  Exceptions  :

=cut

sub print_method_link_species_sets_to_update_by_collection {
    my ($compara_dba, $collection_ss) = @_;

    my $method_link_species_sets = $compara_dba->get_MethodLinkSpeciesSetAdaptor->fetch_all_by_species_set_id($collection_ss->dbID);

    return unless $method_link_species_sets->[0];

    print "List of Bio::EnsEMBL::Compara::MethodLinkSpeciesSet to update:\n";
    foreach my $this_method_link_species_set (sort {$a->dbID <=> $b->dbID} @$method_link_species_sets) {
        printf "%8d: ", $this_method_link_species_set->dbID,;
        print $this_method_link_species_set->method->type, " (", $this_method_link_species_set->name, ")\n";
        if ($this_method_link_species_set->url) {
            $this_method_link_species_set->url('');
            $compara_dba->dbc->do('UPDATE method_link_species_set SET url = "" WHERE method_link_species_set_id = ?', undef, $this_method_link_species_set->dbID);
        }
    }
    print "  NONE\n" unless scalar(@$method_link_species_sets);

}

sub create_species_set {
    my ($genome_dbs, $species_set_name) = @_;
    $species_set_name ||= join('-', sort map {$_->get_short_name} @{$genome_dbs});
    return Bio::EnsEMBL::Compara::SpeciesSet->new(
        -GENOME_DBS => $genome_dbs,
        -NAME => $species_set_name,
    );
}

sub create_mlss {
    my ($method, $species_set, $source, $url) = @_;
    if (ref($species_set) eq 'ARRAY') {
        $species_set = create_species_set($species_set);
    }
    my $ss_display_name = $species_set->get_value_for_tag('display_name');
    {
        $ss_display_name ||= $species_set->name;
        $ss_display_name =~ s/collection-//;
        my $ss_size = scalar(@{$species_set->genome_dbs});
        my $is_aln = $method->class =~ /^(GenomicAlign|ConstrainedElement|ConservationScore|Synteny)/;
        $ss_display_name = "$ss_size $ss_display_name" if $is_aln && $ss_size > 2;
    }
    my $mlss_name = sprintf('%s %s', $ss_display_name, $method->display_name || die "No description for ".$method->type);
    return Bio::EnsEMBL::Compara::MethodLinkSpeciesSet->new(
        -SPECIES_SET => $species_set,
        -METHOD => $method,
        -NAME => $mlss_name,
        -SOURCE => $source || 'ensembl',
        -URL => $url,
    );
}

sub create_mlsss_on_singletons {
    my ($method, $genome_dbs) = @_;
    return [map {create_mlss($method, [$_])} @$genome_dbs];
}

sub create_mlsss_on_pairs {
    my ($method, $genome_dbs, $source, $url) = @_;
    my @mlsss;
    my @input_genome_dbs = @$genome_dbs;
    while (my $gdb1 = shift @input_genome_dbs) {
        foreach my $gdb2 (@input_genome_dbs) {
            push @mlsss, create_mlss($method, [$gdb1, $gdb2], undef, $source, $url);
        }
    }
    return \@mlsss;
}

sub create_self_wga_mlsss {
    my ($compara_dba, $gdb) = @_;
    my $species_set = create_species_set([$gdb]);

    # Alignment with LASTZ_NET (for now ... we may turn this into a parameter in the future)
    my $aln_method = $compara_dba->get_MethodAdaptor->fetch_by_type('LASTZ_NET');
    my $self_lastz_mlss = create_mlss($aln_method, $species_set);
    $self_lastz_mlss->add_tag( 'species_set_size', 1 );
    $self_lastz_mlss->name( $self_lastz_mlss->name . ' (self-alignment)' );

    if ($gdb->is_polyploid) {
        # POLYPLOID is the restriction of the alignment on the homoeologues
        my $pp_method = $compara_dba->get_MethodAdaptor->fetch_by_type('POLYPLOID');
        my $pp_mlss = create_mlss($pp_method, $species_set);
        # Pairwise MLSSs between the components
        my $sub_aln_mlsss = create_mlsss_on_pairs($aln_method, $gdb->component_genome_dbs);
        # Those MLSSs should remain internal
        $_->{_no_release} = 1 for @$sub_aln_mlsss;
        return [$self_lastz_mlss, $pp_mlss, @$sub_aln_mlsss];
    }
    return [$self_lastz_mlss];
}

sub create_pairwise_wga_mlsss {
    my ($compara_dba, $method, $ref_gdb, $nonref_gdb) = @_;
    my @mlsss;
    my $species_set = create_species_set([$ref_gdb, $nonref_gdb]);
    my $pw_mlss = create_mlss($method, $species_set);
    $pw_mlss->add_tag( 'reference_species', $ref_gdb->name );
    $pw_mlss->name( $pw_mlss->name . sprintf('  (on %s)', $ref_gdb->get_short_name) );
    push @mlsss, $pw_mlss;
    if ($ref_gdb->has_karyotype and $nonref_gdb->has_karyotype) {
        my $synt_method = $compara_dba->get_MethodAdaptor->fetch_by_type('SYNTENY');
        push @mlsss, create_mlss($synt_method, $species_set);
    }
    return \@mlsss;
}

sub create_multiple_wga_mlsss {
    my ($compara_dba, $method, $species_set, $with_gerp, $source, $url) = @_;
    my @mlsss;
    push @mlsss, create_mlss($method, $species_set, $source, $url);
    if ($with_gerp) {
        my $ce_method = $compara_dba->get_MethodAdaptor->fetch_by_type('GERP_CONSTRAINED_ELEMENT');
        push @mlsss, create_mlss($ce_method, $species_set, $source, $url);
        my $cs_method = $compara_dba->get_MethodAdaptor->fetch_by_type('GERP_CONSERVATION_SCORE');
        push @mlsss, create_mlss($cs_method, $species_set, $source, $url);
    }
    if ($method->type eq 'CACTUS_HAL') {
        my $pw_method = $compara_dba->get_MethodAdaptor->fetch_by_type('CACTUS_HAL_PW');
        push @mlsss, @{ create_mlsss_on_pairs($pw_method, $species_set->genome_dbs, $source, $url) };
    }
    return \@mlsss;
}

sub create_assembly_patch_mlsss {
    my ($compara_dba, $genome_db) = @_;
    my $species_set = create_species_set([$genome_db]);
    my @mlsss;
    foreach my $method_type (qw(LASTZ_PATCH ENSEMBL_PROJECTIONS)) {
        my $method = $compara_dba->get_MethodAdaptor->fetch_by_type($method_type);
        push @mlsss, create_mlss($method, $species_set);
    }
    return \@mlsss,
}

sub create_homology_mlsss {
    my ($compara_dba, $method, $species_set) = @_;
    my @mlsss;
    push @mlsss, create_mlss($method, $species_set);
    if (($method->type eq 'PROTEIN_TREES') or ($method->type eq 'NC_TREES')) {
        my @non_components = grep {!$_->genome_component} @{$species_set->genome_dbs};
        my $orth_method = $compara_dba->get_MethodAdaptor->fetch_by_type('ENSEMBL_ORTHOLOGUES');
        push @mlsss, @{ create_mlsss_on_pairs($orth_method, \@non_components) };
        my $para_method = $compara_dba->get_MethodAdaptor->fetch_by_type('ENSEMBL_PARALOGUES');
        push @mlsss, @{ create_mlsss_on_singletons($para_method, \@non_components) };
        my $homoeo_method = $compara_dba->get_MethodAdaptor->fetch_by_type('ENSEMBL_HOMOEOLOGUES');
        foreach my $gdb (@{$species_set->genome_dbs}) {
            push @mlsss, create_mlss($homoeo_method, [$gdb]) if $gdb->is_polyploid;
        }
    }
    return \@mlsss;
}

sub _sum {
    my (@items) = @_;
    my $res;
    for my $next (@items) {
        die unless ( defined $next );
        $res += $next;
    }
    return $res;
}

sub _mean {
    my (@items) = @_;
    return _sum(@items)/( scalar @items );
}

1;
