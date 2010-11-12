package Net::SAML2::IdP;
use strict;
use warnings;

=head1 NAME

Net::SAML2::IdP - SAML Identity Provider object

=head1 SYNOPSIS

  my $idp = Net::SAML2::IdP->new_from_url($IDP);
  my $sso_url = $idp->sso_url('urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect');

=head1 METHODS

=cut

use HTTP::Request::Common;
use LWP::UserAgent;
use XML::XPath;

=head2 new_from_url($url)

Create an IdP object by retrieving the metadata at the given URL.

Dies if the metadata can't be retrieved.

=cut

sub new_from_url {
        my ($class, $url) = @_;
        
        my $req = GET $url;
        my $ua = LWP::UserAgent->new;

        my $res = $ua->request($req);
        die "no metadata" unless $res->is_success;
        my $xml = $res->content;

	return $class->new($xml);
}

=head2 new($xml)

Constructor. Create an IdP object using the provided metadata XML
document.

=cut

sub new {
	my ($class, $xml) = @_;
        my $self = bless {}, $class;

        my $xpath = XML::XPath->new( xml => $xml );
        $xpath->set_namespace('md', 'urn:oasis:names:tc:SAML:2.0:metadata');
	$xpath->set_namespace('ds', 'http://www.w3.org/2000/09/xmldsig#');

	my ($desc) = $xpath->findnodes('//md:EntityDescriptor');
	if (defined $desc) {
		$self->{entityID} = $desc->getAttribute('entityID');
	}
	else {
		die "can't find entityID in metadata";
	}

        my @ssos = $xpath->findnodes('//md:EntityDescriptor/md:IDPSSODescriptor/md:SingleSignOnService');
        for my $sso (@ssos) {
                my $binding = $sso->getAttribute('Binding');
                $self->{SSO}->{$binding} = $sso->getAttribute('Location');
        }

        my @slos = $xpath->findnodes('//md:EntityDescriptor/md:IDPSSODescriptor/md:SingleLogoutService');
        for my $slo (@slos) {
                my $binding = $slo->getAttribute('Binding');
                $self->{SLO}->{$binding} = $slo->getAttribute('Location');
        }

        my @arts = $xpath->findnodes('//md:EntityDescriptor/md:IDPSSODescriptor/md:ArtifactResolutionService');
        for my $art (@arts) {
                my $binding = $art->getAttribute('Binding');
                $self->{Art}->{$binding} = $art->getAttribute('Location');
        }

	# XXX this cert should get verified by our CA before we trust it
	my @keys = $xpath->findnodes('//md:EntityDescriptor/md:IDPSSODescriptor/md:KeyDescriptor');
	for my $key (@keys) {
		my $use = $key->getAttribute('use');
		my ($text) = $key->findvalue('ds:KeyInfo/ds:X509Data/ds:X509Certificate') =~ /^\s+(.+?)\s+$/s;
		$self->{Cert}->{$use} = 
		     sprintf("-----BEGIN CERTIFICATE-----\n%s\n-----END CERTIFICATE-----\n", $text);
	}

        return $self;
}

=head2 sso_url($binding)

Returns the url for the SSO service using the given binding. Binding
name should be the full URI. 

=cut

sub sso_url {
        my ($self, $binding) = @_;
        return $self->{SSO}->{$binding};
}

=head2 slo_url($binding)

Returns the url for the Single Logout Service using the given
binding. Binding name should be the full URI.

=cut

sub slo_url {
        my ($self, $binding) = @_;
        return $self->{SLO}->{$binding};
}

=head2 art_url($binding)

Returns the url for the Artifact Resolution service using the given
binding. Binding name should be the full URI.

=cut

sub art_url {
        my ($self, $binding) = @_;
        return $self->{Art}->{$binding};
}

=head2 cert($use)

Returns the IdP's certificate for the given use (e.g. 'signing').

=cut

sub cert {
	my ($self, $use) = @_;
	return $self->{Cert}->{$use};
}

=head2 entityID()

Returns the IdP's entityID, for use as the Destination in requests.

=cut

sub entityID {
	my ($self) = @_;
	return $self->{entityID};
}

=head2 metadata

Returns IdP metadata for this instance

=cut

sub metadata {
	my ($self) = @_;

	return <<"METADATA";
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<md:EntityDescriptor entityID="$self->{id}" xmlns:md="urn:oasis:names:tc:SAML:2.0:metadata">
    <md:IDPSSODescriptor WantAuthnRequestsSigned="false" protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol">
        <md:KeyDescriptor use="signing">
            <ds:KeyInfo xmlns:ds="http://www.w3.org/2000/09/xmldsig#">
                <md:ds:X509Data>
                    <ds:X509Certificate>
$self->{cert}
                    </ds:X509Certificate>
                </ds:X509Data>
            </ds:KeyInfo>
        </md:KeyDescriptor>
        <md:ArtifactResolutionService index="0" isDefault="true" Binding="urn:oasis:names:tc:SAML:2.0:bindings:SOAP" Location="$self->{url}/ArtifactResolver"/>
        <md:SingleLogoutService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect" Location="$self->{url}/IDPSloRedirect" ResponseLocation="$self->{url}/IDPSloRedirect"/>
        <md:SingleLogoutService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST" Location="$self->{url}/IDPSloPOST" ResponseLocation="$self->{url}/IDPSloPOST"/>
        <md:SingleLogoutService Binding="urn:oasis:names:tc:SAML:2.0:bindings:SOAP" Location="$self->{url}/IDPSloSoap"/>
        <md:NameIDFormat>urn:oasis:names:tc:SAML:2.0:nameid-format:persistent</md:NameIDFormat>
        <md:NameIDFormat>urn:oasis:names:tc:SAML:2.0:nameid-format:transient</md:NameIDFormat>
        <md:NameIDFormat>urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress</md:NameIDFormat>
        <md:NameIDFormat>urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified</md:NameIDFormat>
        <md:SingleSignOnService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect" Location="$self->{url}/SSORedirect"/>
        <md:SingleSignOnService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST" Location="$self->{url}/SSOPOST"/>
        <md:SingleSignOnService Binding="urn:oasis:names:tc:SAML:2.0:bindings:SOAP" Location="$self->{url}/SSOSoap"/>
    </md:IDPSSODescriptor>
</md:EntityDescriptor>
METADATA
}

1;
