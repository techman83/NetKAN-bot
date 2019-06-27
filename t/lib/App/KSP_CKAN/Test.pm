package App::KSP_CKAN::Test;

use v5.010;
use strict;
use warnings;
use autodie;
use Method::Signatures 20140224;
use Try::Tiny;
use File::Temp qw(tempdir);
use File::Path qw(remove_tree mkpath);
use File::chdir;
use File::Copy::Recursive qw(dircopy dirmove);
use File::Copy qw(copy);
use Capture::Tiny qw(capture);
use Moo;
use namespace::clean;

# ABSTRACT: There is a bunch of common environment setup for testing.

# VERSION: Generated by DZP::OurPkg:Version

=head1 SYNOPSIS

  use App::KSP_CKAN::Test;

  my $test = App::KSP_CKAN::Test->new();

=head1 DESCRIPTION

This is a helper lib to make setting up our test environment quicker.

'tmp' can be used as a named argument to provide your own temp path.

=cut

has 'tmp'     => ( is => 'ro', lazy => 1, builder => 1 );
has '_tmp'    => ( is => 'ro', lazy => 1, builder => 1 );

method _build_tmp {
  return File::Temp::tempdir();
}

method _build__tmp {
  # Populate our test data
  dircopy("t/data", $self->tmp."/data");

  return $self->tmp;
}

method _random_string {
  # Lets us generate CKANs that are different.
  # http://www.perlmonks.org/?node_id=233023
  my @chars = ("A".."Z", "a".."z");
  my $rand;
  $rand .= $chars[rand @chars] for 1..8;
  return $rand;
}

=method create_tmp

  $test->create_tmp;

This will deploy our temp environment. Only required if we
aren't creating a repo (one will be built on demand).

=cut

method create_tmp {
  $self->_tmp;
  return;
}

=method create_repo

  $test->create_repo('CKAN-meta');

Turns the named repo into a working local remote.

=cut

method create_repo($repo) {
  local $CWD = $self->_tmp."/data/$repo";
  capture { system("git", "init") };
  capture { system("git", "add", "-A") };
  capture { system("git", "commit", "-a", "-m", "Commit ALL THE THINGS!") };
  chdir("../");
  dirmove("$repo", "$repo-tmp");
  capture { system("git", "clone", "--bare", "$repo-tmp", "$repo") };
  return;
}

=method create_ckan

  $test->create_ckan(file => "/path/to/file");

Creates an example ckan that would pass validation at the specified
path.

  $test->create_ckan( file => "/path/to/file" );

=over

=item file

Path and file we are creating.

=item kind

Allows us to specify a different kind of package. 'metadata' is the
only accepted one at the moment.

=item license

Allows us to specify a different license.

=back

=cut

method create_ckan(
  :$file,
  :$random      = 1,
  :$identifier  = "ExampleKAN",
  :$kind        = "package",
  :$license     = '"CC-BY-NC-SA"',
  :$download    = "https://example.com/example.zip",
  :$sha256      = "1A2B3C4D5E1A2B3C4D5E",
  :$version     = "1.0.0.1",
) {
  my $attribute = "identifier";
  my $rand = $random ? $self->_random_string : "random";

  # Allows us against a metapackage. TODO: make into valid metapackage
  my $package;
  if ( $kind eq "metapackage" ) {
    $package = '"kind": "metapackage"';
  } elsif ( $kind eq "nohash" ) {
    $package = qq|"download": "$download","download_content_type": "text/plain"|;
  } else {
    $package = qq|"download": "$download","download_hash": { "sha1": "1A2B3C4D5E","sha256": "$sha256" }, "download_content_type": "application/zip"|;
  }

  # Create the CKAN
  open my $in, '>', $file;
  print $in qq|{"spec_version": 1, "$attribute": "$identifier", "license": $license, "ksp_version": "1.1.2", "name": "Example KAN", "abstract": "It's a $rand example!", "author": "Techman83", "version": "$version", $package, "resources": { "homepage": "https://example.com/homepage", "repository": "https://example.com/repository" }}|;
  close $in;
  return;
}

=method cleanup

  $test->cleanup;

Does what it says on the tin, cleans up our mess.

=cut

=method create_config

  $test->create_config( optional => 0 );

Creates a dummy config file for testing. The 'optional'
defaults to true if unspecified, generating a test config
with optional values.

=cut

=method create_netkan

  $test->create_netkan(file => "/path/to/file");

Creates an example netkan that would pass validation at the specified
path.

=over

=item file

Path and file we are creating.

=item identifier

Allows us to specify a different identifier

=item kref

Allows us to specify a different kref.

=item vref

Allows us to specify a different or undef vref.

=back

=cut

method create_netkan(
  :$file,
  :$identifier  = "DogeCoinFlag",
  :$kref        = "#/ckan/github/pjf/DogeCoinFlag",
  :$vref        = "#/ckan/ksp-avc",
  :$staging     = 0,
  :$random      = 1,
) {
  my $vref_field = $vref ? qq|"\$vref" : "$vref",| : "";
  my $staging_field = $vref ? "" : qq|,"x_netkan_staging" : 1|;
  my $rand = $random ? $self->_random_string : "random";

  # Create the NetKAN
  open my $in, '>', $file;
  print $in qq|{"spec_version": 1, "identifier": "$identifier", "\$kref" : "$kref", $vref_field "license": "CC-BY", "ksp_version": "any", "name": "Example NetKAN", "abstract": "It's a $rand example!", "author": "daviddwk", "resources": { "homepage": "https://www.reddit.com/r/dogecoin/comments/1tdlgg/i_made_a_more_accurate_dogecoin_and_a_ksp_flag/" }$staging_field }|;
  close $in;
  return;
}

method create_config(:$optional = 1, :$nogh = 0) {
  open my $in, '>', $self->_tmp."/.ksp-ckan";
  print $in "CKAN_meta=".$self->_tmp."/data/CKAN-meta\n";
  print $in "NetKAN=".$self->_tmp."/data/NetKAN\n";
  print $in "netkan_exe=https://ckan-travis.s3.amazonaws.com/netkan.exe\n";
  print $in "IA_access=12345678\n";
  print $in "IA_secret=87654321\n";

  # TODO: This is a little ugly.
  if ($optional) {
    if (!$nogh) {
      my $token = $ENV{GH_token} // '123456789';
      print $in "GH_token=$token\n";
    }
    print $in "working=".$self->_tmp."/working\n";
    print $in "cache=".$self->_tmp."/cache\n";
    print $in "IA_collection=collection\n";
  }

  close $in;
  return;
}

=method cleanup

  $test->cleanup;

Does what it says on the tin, cleans up our mess.

=cut

method cleanup {
  if ( -d $self->_tmp ) {
    remove_tree($self->_tmp);
  }
  return;
}

1;
