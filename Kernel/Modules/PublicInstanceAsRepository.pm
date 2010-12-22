# --
# Kernel/Modules/PublicInstanceAsRepository.pm - provides a local repository
# Copyright (C) 2001-2009 OTRS AG, http://otrs.org/
# --
# $Id: PublicInstanceAsRepository.pm,v 1.12 2009/02/16 11:20:53 tr Exp $
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::PublicInstanceAsRepository;

use strict;
use warnings;

use Kernel::System::Package;
use Kernel::System::InstanceAsRepository;

use vars qw($VERSION);
$VERSION = qw($Revision: 1.12 $) [1];

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    # check needed objects
    for my $NeededObject (qw(ParamObject LayoutObject LogObject ConfigObject MainObject)) {
        if ( !$Self->{$NeededObject} ) {
            $Self->{LayoutObject}->FatalError( Message => "Got no $NeededObject!" );
        }
    }

    # create needed objects
    $Self->{PackageObject}    = Kernel::System::Package->new(%Param);
    $Self->{RepositoryObject} = Kernel::System::InstanceAsRepository->new(%Param);

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $File = $Self->{ParamObject}->GetParam( Param => 'File' ) || '';
    $File =~ s/^\///g;

    my $AccessControlIPs = $Self->{ConfigObject}->Get('Package::RepositoryAccessIPs');

    if ( !$AccessControlIPs ) {
        return $Self->{LayoutObject}->ErrorScreen(
            Message => 'Need config Package::RepositoryAccessIPs',
        );
    }

    $AccessControlIPs = [] if ref $AccessControlIPs ne 'ARRAY';
    
    my $HasAccess = grep{ $ENV{REMOTE_ADDR} eq $_ }@{$AccessControlIPs};
    if ( !$HasAccess ) {
        return $Self->{LayoutObject}->ErrorScreen(
            Message => "Authentication failed from $ENV{REMOTE_ADDR}!",
        );
    }

    # get repository index
    if ( $File =~ /otrs.xml$/ ) {

        # get repository index
        my $Index = "<?xml version=\"1.0\" encoding=\"utf-8\" ?>";
        $Index .= "<otrs_package_list version=\"1.0\">\n";
        my @List = $Self->{RepositoryObject}->RepositoryList();

        OPMPACKAGE:
        for my $Package (@List) {

            next OPMPACKAGE if !$Package->{Approved}->{Content};
            next OPMPACKAGE if $Package->{Approved}->{Content} ne $Package->{Version}->{Content};

            $Index .= "<Package>\n";
            $Index .= "  <File>$Package->{Name}->{Content}-$Package->{Version}->{Content}</File>\n";
            $Index .= $Self->{PackageObject}->PackageBuild( %{$Package}, Type => 'Index' );
            $Index .= "</Package>\n";
        }

        $Index .= "</otrs_package_list>\n";

        return $Self->{LayoutObject}->Attachment(
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

        my $IsApproved = $Self->{RepositoryObject}->PackageIsApproved(
            Name => $Name,
            Version => $Version,
        );

        if ( !$IsApproved ) {
            $Name    = '';
            $Version = '';
        }

        my $Package = $Self->{PackageObject}->RepositoryGet(
            Name    => $Name,
            Version => $Version,
        );

        return $Self->{LayoutObject}->Attachment(
            Type        => 'inline',           # inline|attachment
            Filename    => "$Name-$Version",
            ContentType => 'text/xml',
            Content     => $Package,
        );
    }
}

1;
