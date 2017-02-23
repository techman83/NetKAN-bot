package App::KSP_CKAN::Metadata::Releases;

use v5.010;
use strict;
use warnings;
use autodie;
use Method::Signatures 20140224;
use Config::JSON; # Saves us from file handling
use Carp qw(croak);
use Moo;
use namespace::clean;

# ABSTRACT: Metadata Wrapper for releases boundaries

# VERSION: Generated by DZP::OurPkg:Version

=head1 SYNOPSIS

  use App::KSP_CKAN::Metadata::Releases;

  my $releases = App::KSP_CKAN::Metadata::Releases->new(
    file => "/path/to/releases.json",
  );

=head1 DESCRIPTION

Provides a releases metadata object for KSP-CKAN. Has the following
attributes available.

=cut

has 'file'                  => ( is => 'ro', required => 1 ); # TODO: we should do some validation here.
has '_raw'                  => ( is => 'ro', lazy => 1, builder => 1 );
has 'releases'              => ( is => 'ro', lazy => 1, builder => 1 );

# TODO: We're already using file slurper + JSON elsewhere. We should
#       pick one method for consistency.
# TODO: This could also barf out on an invalid file, we'll need to
#       Handle that somewhere.
method _build__raw {
  return Config::JSON->new($self->file);
}

=method releases

  $releases->releases;

Returns an array_ref of the releases.

=cut

method _build_releases {
  my $releases = $self->_raw->{config}{releases};
  foreach my $release (@{$releases}) {
    croak "master will obliterate the main repo, use a different release name" if $release->{name} eq "master";
    $release->{upper} = $release->{upper} ? $release->{upper} : "100.0.0";
    $release->{lower} = $release->{lower} ? $release->{lower} : "0.0.0";
  }
  return $releases;
}

method _compare_version($a, $b) {
  # Shortcut if we're equal
  return 1 if ($a eq $b);

  # Split version into major/minor/patch components
  my @a_split = split(/\./, $a);
  my @b_split = split(/\./, $b);

  # Ensure 0.90 and 1.2 end up as 0.90.0 and 1.2.0
  $a_split[2] = 0 if (! $a_split[2]);
  $b_split[2] = 0 if (! $b_split[2]);

  # This loop will iterate over Major.Minor.Patch
  # As soon as it encounters a situation where $a is
  # less than b it'll return false, alternatively
  # as soon as it encounters a situation where $a is
  # greater than $b it'll return true.
  my $count = 0;
  foreach my $iter (@a_split) {
    if ($iter < $b_split[$count]) {
      return 0;
    }
    if ($iter > $b_split[$count]) {
      return 1;
    }
    $count++;
  }

  # In the case of 1.2 vs 1.2.0, we'll fall through the
  # above iteration, however we're equal. So lets return
  # as such.
  return 1;
}

=method release

  $release->release("1.0.2");

Returns the corresponding release for the version.

=cut

method release($version) {
  # Any is special, it will always end up in the current branch
  return @{$self->releases}[0]->{name} if ($version eq "any");

  foreach my $release (@{$self->releases}) {
    if ( $self->_compare_version($release->{upper}, $version)
        && $self->_compare_version($version, $release->{lower})) {
      return $release->{name};
    }
  }
}
1;
