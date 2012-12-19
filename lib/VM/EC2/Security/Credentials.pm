package VM::EC2::Security::Credentials;

=head1 NAME

VM::EC2::Security::Credentials -- Temporary security credentials for EC2

=head1 SYNOPSIS

 use VM::EC2;
 use VM::EC2::Security::Policy

 # under your account
 $ec2 = VM::EC2->new(...);  # as usual
 my $policy = VM::EC2::Security::Policy->new;
 $policy->allow('DescribeImages','RunInstances');
 my $token = $ec2->get_federation_token(-name     => 'TemporaryUser',
                                        -duration => 60*60*3, # 3 hrs, as seconds
                                        -policy   => $policy);
 print $token->sessionToken,"\n";
 print $token->accessKeyId,"\n";
 print $token->secretAccessKey,"\n";
 print $token->federatedUser,"\n";

 my $serialized = $token->serialize;

 # get the serialized token to the temporary user
 send_data_to_user_somehow($serialized); 

 # under the temporary user's account
 my $serialized = get_data_somehow();

 # create a copy of the token from its serialized form
 my $token = VM::EC2::Security::Credentials->new_from_serialized($serialized);

 # create a copy of the token from its JSON representation (e.g. as returned
 # from instance metadata of an instance that is assigned an IAM role
 my $token = VM::EC2::Security::Credentials->new_from_json($json);

 # open a new EC2 connection with this token. User will be
 # able to run all the methods specified in the policy.
 my $ec2   = VM::EC2->new(-security_token => $token);
 print $ec2->describe_images(-owner=>'self');

 # convenience routine; will return a VM::EC2 object authorized
 # to use the current token
 my $ec2   = $token->new_ec2;
 print $ec2->describe_images(-owner=>'self');
 

=head1 DESCRIPTION

The VM::EC2::Security::Credentials object is returned by the
VM::EC2::Security::Token->credentials() method, which in turn is
generated by calls to VM::EC2->get_federation_token() and
VM::EC2->get_session_token(). The Credentials object contains
time-limited EC2 authentication information, including access key ID,
secret access key, and a temporary authentication session token.

A Credentials object can be passed to VM::EC2->new() via the
-security_token parameter, in which case the -access_key and
-secret_key parameters can be omitted.

As Credentials typically need to be transmitted from a process being
run by an AWS account holder to a process being run by another user,
the object provides serialization methods that allow the object to be
transmitted as a simple string.

=head1 DATA ACCESS METHODS

 accessKeyId()          -- The temporary access key ID
 secretAccessKey()      -- The secret access key
 sessionToken()         -- The temporary security token, as a long
                              opaque string
 expiration()           -- The expiration time of these credentials, as a
                              DateTime string.

As in all VM::EC2 classes, mixedCase() and
broken_out_with_underscores() names may be used interchangeably.

=head1 SERIALIZATION METHODS

These two methods allow you to serialize the credentials into a string
suitable for sending via SSL, S/MIME or another secure channel, and
then reconstructing the object at the other end. For sending the
credentials to a non-perl process, you can simply retrieve each
individual field (access key, etc) and send them individually.

=head2 $serialized = $credentials->serialize()

Return a serialized form of the object as a base64-encoded
string. Note that the serialized form contains the secret access key
and session token in unencrypted, but very slightly obfuscated, form.

=head2 $credentials = VM::EC2::Security::Credentials->new_from_serialized($serialized)

Given a previously-serialized Credentials object, unserialize it and
return a copy.

=head1 CONVENIENCE METHODS

These are convenience methods.

=head2 $ec2 = $credentials->new_ec2(@args)

Create a new VM::EC2 object which is authorized using the security
token contained in the credentials object. You may pass all the
arguments, such as -endpoint, that are accepted by VM::EC2->new(), but
-access_key and -secret_access_key will be ignored.

=head1 STRING OVERLOADING

When used in a string context, this object will interpolate the

=head1 SEE ALSO

L<VM::EC2>
L<VM::EC2::Generic>

=head1 AUTHOR

Lincoln Stein E<lt>lincoln.stein@gmail.comE<gt>.

Copyright (c) 2011 Ontario Institute for Cancer Research

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut

use strict;
use base 'VM::EC2::Generic';
use Storable 'nfreeze','thaw';
use MIME::Base64 'encode_base64','decode_base64';

sub valid_fields {
    my $self = shift;
    return qw(AccessKeyId Expiration SecretAccessKey SessionToken);
}

# because of AWS inconsistencies and limitations on the autoloaded can() method.
sub secret_access_key { shift->{data}{SecretAccessKey} }
sub access_key_id     { shift->{data}{AccessKeyId}     }
sub session_token     { shift->{data}{SessionToken}    }

sub new_ec2 {
    my $self = shift;
    my @args = @_;
    return VM::EC2->new(-security_token=>$self,
			@args);
}

# serialize the credentials in a packed form
sub serialize {
    my $self = shift;
    my $data = nfreeze($self);
    return encode_base64($data);
}

sub new_from_serialized {
    my $class = shift;
    my $data  = shift;
    my $obj   = thaw(decode_base64($data));
    return bless $obj,ref $class || $class;
}

sub new_from_json {
    my $class = shift;
    my ($data,$endpoint) = @_;
    eval "require JSON; 1" or die "no JSON module installed: $@"
	unless JSON->can('decode');
    my $hash = JSON::from_json($data);

    my $payload = {AccessKeyId     => $hash->{AccessKeyId},
		   SecretAccessKey => $hash->{SecretAccessKey},
		   SessionToken    => $hash->{Token},     # note inconsistency here, which is why we are copying
		   Expiration      => $hash->{Expiration}
		   };

    my $self = $class->new($payload,undef);
    my $ec2  = $self->new_ec2(-endpoint => $endpoint);
    $self->ec2($ec2) unless $self->ec2;
    return $self;
}

sub short_name {shift->access_key_id}

1;
