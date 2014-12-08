# --
# Kernel/Modules/AdminInstanceAsRepository.pm - manage software packages
# Copyright (C) 2014 Perl-Services.de, http://perl-services.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::AdminInstanceAsRepository;

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

    my $PackageID = $ParamObject->GetParam( Param => 'PackageID' );

    # ------------------------------------------------------------ #
    # approve package
    # ------------------------------------------------------------ #
    if ( $Self->{Subaction} eq 'Approve' ) {
        $RepositoryObject->PackageApprove(
            PackageID => $PackageID,
            UserID    => $Self->{UserID},
        );
    }

    
    # ------------------------------------------------------------ #
    # download package
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'Download' ) {
        my %Info = $RepositoryObject->RepositoryGet(
            PackageID => $PackageID,
            Result    => 'INFO',
        );

        if ( !%Info ) {
            return $LayoutObject->ErrorScreen( Message => 'No such package!' );
        }

        return $LayoutObject->Attachment(
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
        $RepositoryObject->PackageRevoke(
            PackageID => $PackageID,
        );
    }

    my @Packages = $RepositoryObject->RepositoryList();

    # if there are no local packages to show, a msg is displayed
    if ( !@Packages ) {
        $LayoutObject->Block(
            Name => 'NoPackages',
            Data => {},
        );
    }

    for my $Package (@Packages) {
        my $PackageID = $Package->{PackageID};

        my %Data = $Self->_MessageGet( Info => $Package->{Description} );

        $LayoutObject->Block(
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
            $LayoutObject->Block(
                Name => 'ApprovalLink',
                Data => {
                    PackageID => $PackageID,
                },
            );
        }
        else {
            $LayoutObject->Block(
                Name => 'RevokeLink',
                Data => {
                    PackageID => $PackageID,
                },
            );
        }

    }

    my $Output = $LayoutObject->Header();
    $Output .= $LayoutObject->NavigationBar();
    $Output .= $LayoutObject->Output(
        TemplateFile => 'AdminInstanceAsRepository',
    );
    $Output .= $LayoutObject->Footer();
    return $Output;
}

sub _MessageGet {
    my ( $Self, %Param ) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

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
                    && $Tag->{Lang} eq $ConfigObject->Get('DefaultLanguage')
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
