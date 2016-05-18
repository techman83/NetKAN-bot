package App::KSP_CKAN::Tools::Config;

use v5.010;
use strict;
use warnings;
use autodie;
use Method::Signatures 20140224;
use Config::Tiny;
use Carp qw( croak );
use File::Path qw( mkpath );
use Moo;
use namespace::clean;

# ABSTRACT: A lite wrapper around Config::Tiny

# VERSION: Generated by DZP::OurPkg:Version

=head1 SYNOPSIS

  use App::KSP_CKAN::Git;

  my $git = App::KSP_CKAN::Config->new(
    file => "/path/to/file",
  );

=head1 DESCRIPTION

Provides a config object for KSP-CKAN

=cut

has 'file'          => ( is => 'ro', default => sub { $ENV{HOME}."/.ksp-ckan" } );
has '_config'       => ( is => 'ro', lazy => 1, builder => 1 );
has 'CKAN_meta'     => ( is => 'ro', lazy => 1, builder => 1 );
has 'NetKAN'        => ( is => 'ro', lazy => 1, builder => 1 );
has 'netkan_exe'    => ( is => 'ro', lazy => 1, builder => 1 );
has 'ckan_validate' => ( is => 'ro', lazy => 1, builder => 1 );
has 'ckan_schema'   => ( is => 'ro', lazy => 1, builder => 1 );
has 'GH_token'      => ( is => 'ro', lazy => 1, builder => 1 );
has 'IA_access'     => ( is => 'ro', lazy => 1, builder => 1 );
has 'IA_secret'     => ( is => 'ro', lazy => 1, builder => 1 );
has 'IA_collection' => ( is => 'ro', lazy => 1, builder => 1 );
has 'cache'         => ( is => 'ro', lazy => 1, builder => 1 );
has 'working'       => ( is => 'ro', lazy => 1, builder => 1 );
has 'debugging'     => ( is => 'ro', default => sub { 0 } );

method _build__config {
  if ( ! -e $self->file ) {
    croak( "No config at ".$self->file );
  }
  return Config::Tiny->read( $self->file );
}

method _build_CKAN_meta {
  croak( "Missing 'CKAN_meta' from config" ) if ! $self->_config->{_}{'CKAN_meta'};
  return $self->_config->{_}{'CKAN_meta'};
}

method _build_NetKAN {
  croak( "Missing 'NetKAN' from config" ) if ! $self->_config->{_}{'NetKAN'};
  return $self->_config->{_}{'NetKAN'};
}

method _build_netkan_exe {
  croak( "Missing 'NetKAN' from config" ) if ! $self->_config->{_}{'netkan_exe'};
  return $self->_config->{_}{'netkan_exe'};
}

method _build_ckan_validate {
  croak( "Missing 'ckan_validate' from config" ) if ! $self->_config->{_}{'ckan_validate'};
  return $self->_config->{_}{'ckan_validate'};
}

method _build_ckan_schema {
  croak( "Missing 'ckan_schema' from config" ) if ! $self->_config->{_}{'ckan_schema'};
  return $self->_config->{_}{'ckan_schema'};
}

method _build_IA_access {
  croak( "Missing 'IA_access' from config" ) if ! $self->_config->{_}{'IA_access'};
  return $self->_config->{_}{'IA_access'};
}

method _build_IA_secret {
  croak( "Missing 'IA_secret' from config" ) if ! $self->_config->{_}{'IA_secret'};
  return $self->_config->{_}{'IA_secret'};
}

method _build_IA_collection {
  return $self->_config->{_}{'IA_collection'} ? $self->_config->{_}{'IA_collection'} : "test_collection";
}

method _build_GH_token {
  if ( ! $self->_config->{_}{'GH_token'} ) {
    return 0;
  } else {
    return $self->_config->{_}{'GH_token'};
  }
}

method _build_cache {
  my $cache;
  if ( ! $self->_config->{_}{'cache'} ) {
    $cache = $self->working."/cache";
  } else {
    $cache = $self->_config->{_}{'cache'};
  }

  if ( ! -d $cache ) {
    mkpath($cache);
  }
  return $cache;
}

method _build_working {
  my $working;
  if ( ! $self->_config->{_}{'working'} ) {
    $working = $ENV{HOME}."/CKAN-working";
  } else {
    $working = $self->_config->{_}{'working'};
  }

  if ( ! -d $working ) {
    mkpath($working);
  }
  return $working;
}

1;
