# --
# Kernel/Modules/AdminInstanceAsRepository.pm - manage software packages
# Copyright (C) 2001-2010 OTRS AG, http://otrs.org/
# --
# $Id: AdminInstanceAsRepository.pm,v 1.96 2010/09/23 08:44:35 mb Exp $
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::AdminInstanceAsRepository;

use strict;
use warnings;

use Kernel::System::Package;
use Kernel::System::InstanceAsRepository;

use vars qw($VERSION);
$VERSION = qw($Revision: 1.96 $) [1];

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    # check needed objects
    for my $Needed (qw(ParamObject DBObject LayoutObject LogObject ConfigObject MainObject)) {
        if ( !$Self->{$Needed} ) {
            $Self->{LayoutObject}->FatalError( Message => "Got no $Needed!" );
        }
    }

    $Self->{PackageObject}    = Kernel::System::Package->new(%Param);
    $Self->{RepositoryObject} = Kernel::System::InstanceAsRepository->new(%Param);

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $PackageID = $Self->{ParamObject}->GetParam( Param => 'PackageID' );

    # ------------------------------------------------------------ #
    # approve package
    # ------------------------------------------------------------ #
    if ( $Self->{Subaction} eq 'Approve' ) {
        $Self->{RepositoryObject}->PackageApprove(
            PackageID => $PackageID,
            UserID    => $Self->{UserID},
        );
    }

    
    # ------------------------------------------------------------ #
    # download package
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'Download' ) {
        my %Info = $Self->{RepositoryObject}->RepositoryGet(
            PackageID => $PackageID,
            Result    => 'INFO',
        );

        if ( !%Info ) {
            return $Self->{LayoutObject}->ErrorScreen( Message => 'No such package!' );
        }

        return $Self->{LayoutObject}->Attachment(
            Content     => $Info{Package},
            ContentType => 'application/octet-stream',
            Filename    => $Info{Name},
            Type        => 'attachment',
        );
    }

    # ------------------------------------------------------------ #
    # revoke approval
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'Revoke' ) {
        $Self->{RepositoryObject}->PackageRevoke(
            PackageID => $PackageID,
        );
    }

    my @Packages = $Self->{RepositoryObject}->RepositoryList();

    # if there are no local packages to show, a msg is displayed
    if ( !@Packages ) {
        $Self->{LayoutObject}->Block(
            Name => 'NoPackages',
            Data => {},
        );
    }

    for my $Package (@Packages) {
        my $PackageID = $Package->{PackageID};

        my %Data = $Self->_MessageGet( Info => $Package->{Description} );

        $Self->{LayoutObject}->Block(
            Name => 'PackageRow',
            Data => {
                Name      => $Package->{Name}->{Content},
                Version   => $Package->{Version}->{Content},
                Desc      => $Data{Description},
                Vendor    => $Package->{Vendor}->{Content},
                PackageID => $PackageID,
            },
        );

        if ( !$Package->{Approved}->{Content} ) {
            $Self->{LayoutObject}->Block(
                Name => 'ApprovalLink',
                Data => {
                    PackageID => $PackageID,
                },
            );
        }
        else {
            $Self->{LayoutObject}->Block(
                Name => 'RevokeLink',
                Data => {
                    PackageID => $PackageID,
                },
            );
        }

    }

    my $Output = $Self->{LayoutObject}->Header();
    $Output .= $Self->{LayoutObject}->NavigationBar();
    $Output .= $Self->{LayoutObject}->Output(
        TemplateFile => 'AdminInstanceAsRepository',
    );
    $Output .= $Self->{LayoutObject}->Footer();
    return $Output;
}

sub _MessageGet {
    my ( $Self, %Param ) = @_;

    my $Title       = '';
    my $Description = '';
    my $Use         = 0;
    if ( $Param{Info} ) {
        for my $Tag ( @{ $Param{Info} } ) {
            if ( $Param{Type} ) {
                next if $Tag->{Type} !~ /^$Param{Type}/i;
            }
            $Use = 1;
            if ( $Tag->{Format} && $Tag->{Format} =~ /plain/i ) {
                $Tag->{Content} = '<pre class="contentbody">' . $Tag->{Content} . '</pre>';
            }
            if ( !$Description && $Tag->{Lang} eq 'en' ) {
                $Description = $Tag->{Content};
                $Title       = $Tag->{Title};
            }
            if (
                ( $Self->{UserLanguage} && $Tag->{Lang} eq $Self->{UserLanguage} )
                || (
                    !$Self->{UserLanguage}
                    && $Tag->{Lang} eq $Self->{ConfigObject}->Get('DefaultLanguage')
                )
                )
            {
                $Description = $Tag->{Content};
                $Title       = $Tag->{Title};
            }
        }
        if ( !$Description && $Use ) {
            for my $Tag ( @{ $Param{Info} } ) {
                if ( !$Description ) {
                    $Description = $Tag->{Content};
                    $Title       = $Tag->{Title};
                }
            }
        }
    }
    return if !$Description && !$Title;
    return (
        Description => $Description,
        Title       => $Title,
    );
}

1;
