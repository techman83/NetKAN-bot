package App::KSP_CKAN::NetKAN;

use v5.010;
use strict;
use warnings;
use autodie;
use Method::Signatures 20140224;
use File::chdir;
use Time::Seconds;
use Carp qw( croak );
use App::KSP_CKAN::Status;
use App::KSP_CKAN::DownloadCounts;
use App::KSP_CKAN::Tools::Http;
use App::KSP_CKAN::Tools::Git;
use App::KSP_CKAN::Tools::NetKAN;
use Moo;
use namespace::clean;

# ABSTRACT: NetKAN Indexing Service

# VERSION: Generated by DZP::OurPkg:Version

=head1 SYNOPSIS

  use App::KSP_CKAN::NetKAN;

  my $netkan = App::KSP_CKAN::NetKAN->new(
    config => $config,
  );

=head1 DESCRIPTION

Is a wrapper for the NetKAN inflater. Initially it will
just wrap and capture errors, but the intention is to 
add helper methods to check for changes in remote meta
data and only run the inflater when required.

=cut

my $Ref = sub {
  croak("auth isn't a 'App::KSP_CKAN::Tools::Config' object!") unless $_[0]->DOES("App::KSP_CKAN::Tools::Config");
};

has 'config'      => ( is => 'ro', required => 1, isa => $Ref );
has '_http'       => ( is => 'ro', lazy => 1, builder => 1 );
has '_CKAN_meta'  => ( is => 'ro', lazy => 1, builder => 1 );
has '_NetKAN'     => ( is => 'ro', lazy => 1, builder => 1 );
has '_status'     => ( is => 'rw', lazy => 1, builder => 1 );

method _build__http {
  return App::KSP_CKAN::Tools::Http->new();
}

method _build__CKAN_meta {
  return App::KSP_CKAN::Tools::Git->new(
    remote  => $self->config->CKAN_meta,
    local   => $self->config->working,
    clean   => 1,
  );
}

method _build__NetKAN {
  return App::KSP_CKAN::Tools::Git->new(
    remote  => $self->config->NetKAN,
    local   => $self->config->working,
    clean   => 1,
  );
}

method _build__status {
  return App::KSP_CKAN::Status->new(
    config => $self->config,
  );
}

method _mirror_files {
  my $config = $self->config;

  # netkan.exe
  $self->_http->mirror( 
    url   => $config->netkan_exe,
    path  => $config->working."/netkan.exe",
    exe   => 1,
  );

  # ckan-validate.py
  $self->_http->mirror(
    url   => $config->ckan_validate,
    path  => $config->working."/ckan-validate.py",
    exe   => 1,
  );

  # CKAN.schema
  $self->_http->mirror(
    url   => $config->ckan_schema,
    path  => $config->working."/CKAN.schema",
  );

  return;
}


method _inflate_all(:$rescan = 1) {
  $self->_CKAN_meta->pull;
  $self->_NetKAN->pull;
  local $CWD = $self->config->working."/".$self->_NetKAN->working;
  foreach my $file (glob("NetKAN/*.netkan")) {
    my $netkan = App::KSP_CKAN::Tools::NetKAN->new(
      config      => $self->config,
      file        => $file,
      ckan_meta   => $self->_CKAN_meta,
      status      => $self->_status,
      rescan      => $rescan,
    );
    $netkan->inflate;
  }
  return;
}

# Calculate the download counts and save them to CKAN-meta/download_counts.json
# Works for mods with a $kref on Curse, GitHub, or SpaceDock.
# Expected to take a few minutes.
method _update_download_counts() {
  my $counter = App::KSP_CKAN::DownloadCounts->new(
    config    => $self->config,
    ckan_meta => $self->_CKAN_meta,
  );
  my $data_age = time() - $counter->last_run;
  if ($data_age >= ONE_DAY) {
    $counter->get_counts;
    $counter->write_json;
  }
}

method _push {
  $self->_CKAN_meta->pull(ours => 1);
  $self->_CKAN_meta->push;
  return;
}

=method full_index 

Performs a full index of the NetKAN metadata and pushes
it into CKAN-meta (or whichever repository is configured)

=cut

method full_index {
  $self->_mirror_files;
  $self->_inflate_all;
  $self->_update_download_counts;
  if ( ! $self->is_debug() ) {
    $self->_push;
    $self->_status->write_json;
  }
  return;
}

=method

**Not Currently Implemented**

Unlike the full index, it will attempt to check options
headers + api data for when a mod was released and only
inflate metadata when required.

=cut

method lite_index {
  $self->_mirror_files;
  $self->_inflate_all( rescan => 0 );
  if ( ! $self->is_debug() ) {
    $self->_push;
    $self->_status->write_json;
  }
  return;
}

with('App::KSP_CKAN::Roles::Logger');

1;
