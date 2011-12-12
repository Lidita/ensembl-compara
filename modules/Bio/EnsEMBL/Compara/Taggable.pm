=head1 LICENSE

  Copyright (c) 1999-2011 The European Bioinformatics Institute and
  Genome Research Limited.  All rights reserved.

  This software is distributed under a modified Apache license.
  For license details, please see

   http://www.ensembl.org/info/about/code_licence.html

=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <dev@ensembl.org>.

  Questions may also be sent to the Ensembl help desk at
  <helpdesk@ensembl.org>.

=head1 NAME

Bio::EnsEMBL::Compara::Taggable

=head1 DESCRIPTION

Base class for objects supporting tags / attributes

=head1 MAINTAINER

$Author$

=head VERSION

$Revision$

=head1 APPENDIX

The rest of the documentation details each of the object methods.
Internal methods are usually preceded with a _

=cut

package Bio::EnsEMBL::Compara::Taggable;

use strict;
use Bio::EnsEMBL::Utils::Exception;
use Bio::EnsEMBL::Utils::Argument;


=head2 add_tag

  Description: adds metadata tags to a node.  Both tag and value are added
               as metdata with the added ability to retreive the value given
               the tag (like a perl hash). In case of one to many relation i.e.
               one tag and different values associated with it, the values are
               returned in a array reference.
  Arg [1]    : <string> tag
  Arg [2]    : <string> value
  Arg [3]    : (optional) <int> allows overloading the tag with different values
               default is 0 (no overloading allowed, one tag points to one value)
  Example    : $ns_node->add_tag('scientific name', 'Mammalia');
               $ns_node->add_tag('lost_taxon_id', 9593, 1);
  Returntype : Boolean indicating if the tag could be stored
  Exceptions : none
  Caller     : general

=cut

sub add_tag {
    my $self = shift;
    my $tag = shift;
    my $value = shift;
    my $allow_overloading = shift;

    # Argument check
    return 0 unless (defined $tag);
    return 0 unless (defined $value);
    $allow_overloading = 0 unless (defined $allow_overloading);
    
    $self->_load_tags;
    $tag = lc($tag);

    if ($allow_overloading and exists $self->{'_attr_list'} and exists $self->{'_attr_list'}->{$tag}) {
        warn "Trying to overload the value of attribute '$tag' ! This is not allowed for $self\n";
        return 0;
    }

    # Stores the value in the PERL object
    if ( ! exists($self->{'_tags'}->{$tag}) || ! $allow_overloading ) {
        # No overloading or new tag: store the value
        $self->{'_tags'}->{$tag} = $value;

    } elsif ( ref($self->{'_tags'}->{$tag}) eq 'ARRAY' ) {
        # Several values were there: we add a new one
        push @{$self->{'_tags'}->{$tag}}, $value;

    } else {
        # One value was there, we make an array
        $self->{'_tags'}->{$tag} = [ $self->{'_tags'}->{$tag}, $value ];
    }
    return 1;
}


=head2 store_tag

  Description: calls add_tag and then stores the tag in the database. Has the
               exact same arguments as add_tag
  Arg [1]    : <string> tag
  Arg [2]    : <string> value
  Arg [3]    : (optional) <int> allows overloading the tag with different values
               default is 0 (no overloading allowed, one tag points to one value)
  Example    : $ns_node->store_tag('scientific name', 'Mammalia');
               $ns_node->store_tag('lost_taxon_id', 9593, 1);
  Returntype : 0 if the tag couldn't be stored,
               1 if it is only in the PERL object,
               2 if it is also stored in the database
  Exceptions : none
  Caller     : general

=cut

sub store_tag {
    my $self = shift;
    my $tag = shift;
    my $value = shift;
    my $allow_overloading = shift;

    if ($self->add_tag($tag, $value, $allow_overloading)) {
        if($self->adaptor and $self->adaptor->isa("Bio::EnsEMBL::Compara::DBSQL::TagAdaptor")) {
            $self->adaptor->_store_tagvalue($self, lc($tag), $value, $allow_overloading);
            return 2;
        } else {
            warn "Calling store_tag on $self but the adaptor ", $self->adaptor, " doesn't have such capabilities\n";
            return 1;
        }
    } else {
        return 0;
    }
}


=head2 delete_tag

  Description: removes a tag from the metadata. If the value is provided, it tries
               to delete only it (if present). Otherwise, it just clears the tag,
               whatever value it was containing
  Arg [1]    : <string> tag
  Arg [2]    : (optional) <string> value
  Example    : $ns_node->remove_tag('scientific name', 'Mammalia');
               $ns_node->remove_tag('lost_taxon_id', 9593);
  Returntype : 0 if the tag couldn't be removed,
               1 if it is only in the PERL object,
               2 if it is also stored in the database
  Exceptions : none
  Caller     : general

=cut

sub delete_tag {
    my $self = shift;
    my $tag = shift;
    my $value = shift;

    # Arguments check
    return 0 unless (defined $tag);
    $tag = lc($tag);

    $self->_load_tags;
    return 0 unless exists($self->{'_tags'}->{$tag});

    # Updates the PERL object
    my $ret = 0;
    if (defined $value) {
        if ( ref($self->{'_tags'}->{$tag}) eq 'ARRAY' ) {
            my $arr = $self->{'_tags'}->{$tag};
            my $index = scalar(@$arr)-1;
            until ($index < 0) {
                $index-- until ($index < 0) or ($arr->[$index] eq $value);
                if ($index >= 0) {
                    splice(@$arr, $index, 1);
                    $ret = 1;
                }
            }
            if (scalar(@$arr) == 0) {
                delete $self->{'_tags'}->{$tag};
            } elsif (scalar(@$arr) == 1) {
                $self->{'_tags'}->{$tag} = $arr->[0];
            }
        } else {
            if ($self->{'_tags'}->{$tag} eq $value) {
                delete $self->{'_tags'}->{$tag};
                $ret = 1;
            }
        }
    } else {
        delete $self->{'_tags'}->{$tag};
        $ret = 1;
    }

    # Update the database
    if ($ret) {
        if($self->adaptor and $self->adaptor->isa("Bio::EnsEMBL::Compara::DBSQL::TagAdaptor")) {
            $self->adaptor->_delete_tagvalue($self, $tag, $value);
            return 2;
        } else {
            return 1;
        }
    } else {
        return 0;
    }
}


=head2 has_tag

  Description: indicates whether the tag exists in the metadata
  Arg [1]    : <string> tag
  Example    : $ns_node->has_tag('scientific name');
  Returntype : Boolean
  Exceptions : none
  Caller     : general

=cut

sub has_tag {
    my $self = shift;
    my $tag = shift;

    return 0 unless defined $tag;

    $self->_load_tags;
    return exists($self->{'_tags'}->{lc($tag)});
}


=head2 get_tagvalue

  Description: returns the value of the tag, or $default (undef
               if not provided) if the tag doesn't exist.
  Arg [1]    : <string> tag
  Arg [2]    : (optional) <string> default
  Example    : $ns_node->get_tagvalue('scientific name');
  Returntype : String
  Exceptions : none
  Caller     : general

=cut

sub get_tagvalue {
    my $self = shift;
    my $tag = shift;
    my $default = shift;

    return $default unless defined $tag;

    $tag = lc($tag);
    $self->_load_tags;
    return $default unless exists($self->{'_tags'}->{$tag});
    return $self->{'_tags'}->{$tag};
}


=head2 get_all_tags

  Description: returns an array of all the available tags
  Example    : $ns_node->get_all_tags();
  Returntype : Array
  Exceptions : none
  Caller     : general

=cut

sub get_all_tags {
    my $self = shift;

    $self->_load_tags;
    return keys(%{$self->{'_tags'}});
}


=head2 get_tagvalue_hash

  Description: returns the underlying hash that contains all
               the tags
  Example    : $ns_node->get_tagvalue_hash();
  Returntype : Hashref
  Exceptions : none
  Caller     : general

=cut

sub get_tagvalue_hash {
    my $self = shift;

    $self->_load_tags;
    return $self->{'_tags'};
}

=head2 _load_tags

  Description: loads all the tags (from the database) if possible.
               Otherwise, an empty hash is created
  Example    : $ns_node->_load_tags();
  Returntype : none
  Exceptions : none
  Caller     : internal

=cut

sub _load_tags {
    my $self = shift;
    return if(defined($self->{'_tags'}));
    $self->{'_tags'} = {};
    if($self->adaptor and $self->adaptor->isa("Bio::EnsEMBL::Compara::DBSQL::TagAdaptor")) {
        $self->adaptor->_load_tagvalues($self);
    }
}


1;

