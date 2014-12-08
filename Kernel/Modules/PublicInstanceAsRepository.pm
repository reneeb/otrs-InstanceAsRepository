# --
# Kernel/Modules/PublicInstanceAsRepository.pm - provides a local repository
# Copyright (C) 2014 Perl-Services.de, http://perl-services.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::PublicInstanceAsRepository;

use strict;
use warnings;

our @ObjectDependencies = qw(
    Kernel::Config
    Kernel::Output::HTML::Layout
    Kernel::System::Web::Request
    Kernel::System::Package
    Kernel::System::InstanceAsRepository
);

our $VERSION = 0.01;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $ParamObject      = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $RepositoryObject = $Kernel::OM->Get('Kernel::System::InstanceAsRepository');
    my $LayoutObject     = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ConfigObject     = $Kernel::OM->Get('Kernel::Config');
    my $PackageObject    = $Kernel::OM->Get('Kernel::System::Package');

    my $File = $ParamObject->GetParam( Param => 'File' ) || '';
    $File =~ s/^\///g;

    my $AccessControlIPs = $ConfigObject->Get('Package::RepositoryAccessIPs');

    if ( !$AccessControlIPs ) {
        return $LayoutObject->ErrorScreen(
            Message => 'Need config Package::RepositoryAccessIPs',
        );
    }

    $AccessControlIPs = [] if ref $AccessControlIPs ne 'ARRAY';
    
    my $HasAccess = grep{ $ENV{REMOTE_ADDR} eq $_ }@{$AccessControlIPs};
    if ( !$HasAccess ) {
        return $LayoutObject->ErrorScreen(
            Message => "Authentication failed from $ENV{REMOTE_ADDR}!",
        );
    }

    # get repository index
    if ( $File =~ /otrs.xml$/ ) {

        # get repository index
        my $Index = "<?xml version=\"1.0\" encoding=\"utf-8\" ?>";
        $Index .= "<otrs_package_list version=\"1.0\">\n";
        my @List = $RepositoryObject->RepositoryList(
            Distinct => 1,
        );

        OPMPACKAGE:
        for my $Package (@List) {

            next OPMPACKAGE if !$Package->{Approved}->{Content};
            next OPMPACKAGE if $Package->{Approved}->{Content} ne $Package->{Version}->{Content};

            $Index .= "<Package>\n";
            $Index .= "  <File>$Package->{Name}->{Content}-$Package->{Version}->{Content}</File>\n";
            $Index .= $PackageObject->PackageBuild( %{$Package}, Type => 'Index' );
            $Index .= "</Package>\n";
        }

        $Index .= "</otrs_package_list>\n";

        return $LayoutObject->Attachment(
            Type        => 'inline',     # inline|attachment
            Filename    => 'otrs.xml',
            ContentType => 'text/xml',
            Content     => $Index,
        );
    }

    # export package
    else {
        my $Name    = '';
        my $Version = '';

        if ( $File =~ /^(.*)\-(.+?)$/ ) {
            $Name    = $1;
            $Version = $2;
        }

        my $IsApproved = $RepositoryObject->PackageIsApproved(
            Name => $Name,
            Version => $Version,
        );

        if ( !$IsApproved ) {
            $Name    = '';
            $Version = '';
        }

        my $Package = $RepositoryObject->RepositoryGet(
            Name    => $Name,
            Version => $Version,
        );

        return $LayoutObject->Attachment(
            Type        => 'inline',           # inline|attachment
            Filename    => "$Name-$Version",
            ContentType => 'text/xml',
            Content     => $Package,
        );
    }
}

1;
