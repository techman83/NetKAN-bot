package App::KSP_CKAN::Tools::NetKAN;

use v5.010;
use strict;
use warnings;
use autodie;
use Method::Signatures 20140224;
use Try::Tiny;
use File::Spec 'tmpdir';
use File::Basename qw(basename);
use File::Path qw(mkpath);
use Capture::Tiny qw(capture);
use Digest::MD5::File qw(dir_md5_hex);
use File::Find::Age;
use Carp qw(croak);
use App::KSP_CKAN::Metadata::NetKAN;
use App::KSP_CKAN::Tools::GitHub;
use Moo;
use namespace::clean;

# ABSTRACT: A wrapper around NetKAN.exe and NetKAN related functions.

# VERSION: Generated by DZP::OurPkg:Version

=head1 SYNOPSIS

  use App::KSP_CKAN::Tools::NetKAN;

  my $netkan = App::KSP_CKAN::Tools::NetKAN->new(
    netkan => "/path/to/netkan.exe",
    chache => "/path/to/cache",
    token => $token,
    file => '/path/to/file.netkan',
    ckan_meta => '/path/to/CKAN-meta',
  );

=head1 DESCRIPTION

Is a wrapper for the NetKAN inflater. Initially it will
just wrap and capture errors, but the intention is to
add helper methods to check for changes in remote meta
data and only run the inflater when required.

=cut

my $Ref = sub {
  croak("config isn't a 'App::KSP_CKAN::Tools::Config' object!") unless $_[0]->DOES("App::KSP_CKAN::Tools::Config");
};

my $Meta = sub {
  croak("ckan-meta isn't a 'App::KSP_CKAN::Tools::Git' object!") unless $_[0]->DOES("App::KSP_CKAN::Tools::Git");
};

my $Status = sub {
  croak("status isn't a 'App::KSP_CKAN::Status' object!") unless $_[0]->DOES("App::KSP_CKAN::Status");
};

has 'config'              => ( is => 'ro', required => 1, isa => $Ref );
has 'file'                => ( is => 'ro', required => 1 );
has 'ckan_meta'           => ( is => 'ro', required => 1, isa => $Meta );
has 'status'              => ( is => 'rw', required => 1, isa => $Status );
has 'rescan'              => ( is => 'ro', default => sub { 1 } );
has 'token'               => ( is => 'ro', lazy => 1, builder => 1 );
has 'netkan'              => ( is => 'ro', lazy => 1, builder => 1 );
has 'cache'               => ( is => 'ro', lazy => 1, builder => 1 );
has '_ckan_meta_working'  => ( is => 'ro', lazy => 1, builder => 1 );
has '_output'             => ( is => 'ro', lazy => 1, builder => 1 );
has '_cli'                => ( is => 'ro', lazy => 1, builder => 1 );
has '_cache'              => ( is => 'ro', lazy => 1, builder => 1 );
has '_basename'           => ( is => 'ro', lazy => 1, builder => 1 );
has '_status'             => ( is => 'rw', lazy => 1, builder => 1 );
has '_netkan_metadata'    => ( is => 'rw', lazy => 1, builder => 1 );
has '_github'             => ( is => 'rw', lazy => 1, builder => 1 );

method _build__cache {
  if ( ! -d $self->cache ) {
    mkpath($self->cache);
  }

  return $self->cache;
}

method _build__basename {
  return basename($self->file,  ".netkan");
}

method _build__ckan_meta_working {
  return $self->config->working."/".$self->ckan_meta->working;
}

method _build__output {
  if (! -d $self->_ckan_meta_working."/".$self->_basename ) {
    mkdir $self->_ckan_meta_working."/".$self->_basename;
  }
  return $self->_ckan_meta_working."/".$self->_basename;
}

method _build__cli {
  if ($self->token) {
    return $self->netkan." --outputdir=".$self->_output." --cachedir=".$self->_cache." --github-token=".$self->token." ".$self->file;
  } else {
    return $self->netkan." --outputdir=".$self->_output." --cachedir=".$self->_cache." ".$self->file;
  }
}

method _build_cache {
  return $self->config->cache;
}

method _build_token {
  return $self->config->GH_token;
}

method _build_netkan {
  return $self->config->working."/netkan.exe";
}

method _build__status {
  return $self->status->get_status($self->_basename);
}

method _build__netkan_metadata {
  return App::KSP_CKAN::Metadata::NetKAN->new( file => $self->file );
}

method _build__github {
  return App::KSP_CKAN::Tools::GitHub->new( config  => $self->config );
}

method _output_md5 {
  my $md5 = Digest::MD5->new();
  $md5->adddir($self->_output);
  return $md5->hexdigest;
}

# Short of hashing every file individually (including
# ones that may not have existed before) we have no
# real way to derive what changed from NetKAN, but the
# Filesystem is kind enough to tell us.
method _newest_file {
  return File::Find::Age->in($self->_output)->[-1]->{file};
}

method _check_lite {
  # TODO: Build a method to go and check if required full inflate
  croak("_check_lite is unimplimented");
  return 0;
}

method _parse_error($error) {
  my $return;
  if ($error =~ /^\d+.\[\d+\].FATAL/m) {
    $error =~ m{FATAL.+?.-.(.+)}m;
    $return = $1;
  } else {
    $error =~ m{^\[ERROR\].(.+)}m;
    $return = $1;
  }
  return $return || "Error wasn't parsable";
}

method _commit($file) {
  $self->ckan_meta->add($file);
  my $changed = basename($file,  ".ckan");

  if ( $self->validate($file) ) {
    $self->warn("Failed to Parse $changed");
    $self->ckan_meta->reset(file => $file);
    $self->ckan_meta->clean_untracked;
    $self->_status->failure("Schema validation failed");
    return 1;
  }

  if ($self->is_debug()) {
    $self->debug("$changed would have been commited");
    $self->ckan_meta->reset(file => $file);
    return 0;
  }

  if ( ! $self->_netkan_metadata->staging ) {
    $self->info("Commiting $changed");
    $self->ckan_meta->commit(
      file    => $file,
      message => "NetKAN generated mods - $changed",
    );
    $self->_status->indexed;
    return 0;
  }

  if ( $self->_netkan_metadata->staging ) {
    my $result = $self->ckan_meta->staged_commit(
      file        => $file,
      identifier  => $self->_netkan_metadata->identifier,
      message     => "NetKAN generated mods - $changed",
    );
    $self->info("Committed $changed to staging") if $result;
    $self->_github->submit_pr($self->_netkan_metadata->identifier) if $self->config->GH_token && $result;
    return 0;
  }

  return 1;
}

method _save_status() {
  $self->status->update_status($self->_basename, $self->_status);
}

=method inflate

  $netkan->inflate;

Inflates our metadata.

=cut

method inflate {
  $self->_status->checked;

  if (! $self->rescan ) {
    $self->_save_status();
    return;
  }

  # We won't know if NetKAN actually made a change and
  # it doesn't know either, it just produces a ckan file.
  # This gives us a hash of all files in the directory
  # before we inflate to compare afterwards.
  my $md5 = $self->_output_md5;

  $self->debug("Inflating ".$self->file);
  my ($stderr, $stdout, $exit) = capture {
    system($self->_cli);
  };

  $self->_status->inflated;

  if ($exit) {
    my $error = $stdout ? $self->_parse_error($stdout) : $self->_parse_error($stderr);
    $self->warn("'".$self->file."' - ".$error);
    $self->_status->failure($error);
    $self->_save_status();
    return $exit;
  }

  if ($md5 ne $self->_output_md5) {
    my $ret = $self->_commit($self->_newest_file);
    $self->_save_status();
    return $ret;
  }

  $self->_status->success;
  $self->_save_status();
  return 0;
}

with('App::KSP_CKAN::Roles::Logger','App::KSP_CKAN::Roles::Validate');

1;
