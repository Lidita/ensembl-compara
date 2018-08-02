=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2018] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 CONTACT

Please email comments or questions to the public Ensembl
developers list at <http://lists.ensembl.org/mailman/listinfo/dev>.

Questions may also be sent to the Ensembl help desk at
<http://www.ensembl.org/Help/Contact>.

=head1 NAME

Bio::EnsEMBL::Compara::Comparable

=head1 DESCRIPTION

Base class that defines methods to compare objects.

=head1 APPENDIX

The rest of the documentation details each of the object methods. Internal methods are usually preceded with a _

=head1 METHODS

=cut


# Let the code begin...


package Bio::EnsEMBL::Compara::Comparable;

use strict;
use warnings;

use Bio::EnsEMBL::Utils::Exception qw(throw);


=head2 _comparable_fields

  Example     : $genome_db->_comparable_fields();
  Description : Return the list of all the fields that should be considered by L<_check_equals>
  Returntype  : List of field names
  Exceptions  : none
  Caller      : general
  Status      : Stable

=cut

sub _comparable_fields {
    my $self = shift;
    throw(ref($self) . " must implement _comparable_fields()");
}


=head2 _check_equals

  Example     : $genome_db->_check_equals($other);
  Description : Check that all the fields are the same as in the other object
  Returntype  : String: all the differences found between the two objects
  Exceptions  : none

=cut

sub _check_equals {
    my ($self, $other) = @_;

    my $type = ref($self);
    $type =~ s/^.*:://;

    my $diffs = '';
    foreach my $field ($self->_comparable_fields) {
        if (($self->$field() xor $other->$field()) or ($self->$field() and $other->$field() and ($self->$field() ne $other->$field()))) {
            $diffs .= sprintf("%s differs between this %s (%s) and the reference one (%s)\n", $field, $type, $self->$field() // '<NULL>', $other->$field() // '<NULL>');
        }
    }
    return $diffs;
}


=head2 _assert_equals

  Example     : $genome_db->_assert_equals($other);
  Description : Wrapper around _check_equals() that will throw if the objects are different
  Returntype  : none
  Exceptions  : Throws if there are discrepancies

=cut

sub _assert_equals {
    my $self = shift;
    my $diffs = $self->_check_equals(@_);
    throw($diffs) if $diffs;
}


1;
