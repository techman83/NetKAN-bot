package App::KSP_CKAN::WebHooks::MirrorCKAN;

use v5.010;
use strict;
use warnings;
use autodie;
use Method::Signatures 20140224;
use File::chdir;
use File::Path qw( mkpath );
use Scalar::Util 'reftype';
use Try::Tiny;
use App::KSP_CKAN::Tools::Config;
use Moo;
use namespace::clean;

extends 'App::KSP_CKAN::Mirror';

# ABSTRACT: CKAN Mirror on demand

# VERSION: Generated by DZP::OurPkg:Version

=head1 SYNOPSIS

  use App::KSP_CKAN::WebHooks::MirrorCKAN;

  my $mirror = App::KSP_CKAN::WebHooks::MirrorCKAN->new();
  $mirror->mirror("/path/to/ckan");

=head1 DESCRIPTION

Webhook wrapper for Mirror CKAN on demand.

=cut

has 'config' => ( is => 'ro', lazy => 1, builder => 1 );
has '_CKAN_meta'  => ( is => 'ro', lazy => 1, builder => 1 );

# TODO: This is a hack, the application should be multi
#       function aware.
method _build_config {
  my $working = $ENV{HOME}."/CKAN-Webhooks/mirror";
  if ( ! -d $working ) {
    mkpath($working);
  }
  return App::KSP_CKAN::Tools::Config->new(
    working => $working,
  );
}

method _build__CKAN_meta {
  return App::KSP_CKAN::Tools::Git->new(
    remote  => $self->config->CKAN_meta,
    local   => $self->config->working,
    clean   => 1,
  );
}

method mirror($files) {
  # Lets take an array as well!
  my @files = reftype \$files ne "SCALAR" ? @{$files} : $files;

  # Prepare Enironment
  $self->_CKAN_meta->pull;
  local $CWD = $self->config->working."/".$self->_CKAN_meta->working;

  foreach my $file (@files) {
    # Lets not try mirroring non existent files
    if (! -e $file) {
      $self->warn("The ckan '".$file."' doesn't appear to exist");
      next;
    }

    # Attempt Mirror
    try {
      $self->upload_ckan($file);
    };
  }

  return 1;
}

1;
