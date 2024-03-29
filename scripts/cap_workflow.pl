#!/usr/bin/env perl
package CAP;

use strict;
use warnings;
#use Config::Simple; # for kbase config


use JSON;

use Data::Dumper;


use AWE::Workflow; # includes Shock::Client

use AWE::Client;

#use Shock::Client; # not clear why I can't use that here ....

1;

sub new {
	my ($class, %h) = @_;
	
	my $self = {
		aweserverurl	=> $ENV{'AWE_SERVER_URL'},
		shockurl		=> $ENV{'SHOCK_SERVER_URL'},
		clientgroup		=> $ENV{'AWE_CLIENT_GROUP'},
		shocktoken		=> $ENV{'KB_AUTH_TOKEN'}
	};
	
	foreach my $key ('aweserverurl', 'shockurl', 'clientgroup', 'shocktoken') {
		if (defined($h{$key}) && $h{$key} ne '') {
			$self->{$key} = $h{$key};
		}
		
		unless (defined $self->{$key} ) {
			die "variable $key not defined";
		}
		
	}
	
	bless $self, $class;
#	$self->readConfig();
	
	
	return $self;
}



sub aweserverurl {
	my ($self, $value) = @_;
	if (defined $value) {
		$self->{'aweserverurl'} = $value;
	}
	return $self->{'aweserverurl'};
}

sub shockurl {
	my ($self) = @_;
	return $self->{'shockurl'};
}

sub clientgroup {
	my ($self, $value) = @_;
	if (defined $value) {
		$self->{'clientgroup'} = $value;
	}
	return $self->{'clientgroup'};
}

sub shocktoken {
	my ($self, $value) = @_;
	if (defined $value) {
		$self->{'shocktoken'} = $value;
	}
	return $self->{'shocktoken'};
}

sub readConfig {
	my ($self) = @_;
	my $conf_file = $ENV{'KB_TOP'}.'/deployment.cfg';
	unless (-e $conf_file) {
		die "error: deployment.cfg not found ($conf_file)";
	}
	my $cfg_full = Config::Simple->new($conf_file );
	my $cfg = $cfg_full->param(-block=>'AmethstService');
	unless (defined $self->{'aweserverurl'} && $self->{'aweserverurl'} ne '') {
		$self->{'aweserverurl'} = $cfg->{'awe-server'};
		unless (defined($self->{'aweserverurl'}) && $self->{'aweserverurl'} ne "") {
			die "awe-server not found in config";
		}
	}
	unless (defined $self->{'shockurl'} && $self->{'shockurl'} ne '') {
		$self->{'shockurl'} = $cfg->{'shock-server'};
		unless (defined(defined $self->{'shockurl'}) && $self->{'shockurl'} ne "") {
			die "shock-server not found in config";
		}
	}
	unless (defined $self->{'clientgroup'} && $self->{'clientgroup'} ne '') {
		$self->{'clientgroup'} = $cfg->{'clientgroup'};
		unless (defined($self->{'clientgroup'}) && $self->{'clientgroup'} ne "") {
			die "clientgroup not found in config";
		}
	}
}


sub other_stuff {
	
	
	#task 1  (khmer)
	# input: *renamed
	#generates simulated metagenomes combined into one file
	#cat *renamed > metagenome-cumulative.fa
	#requires khmer and dependencies
	#python ~/khmer/scripts/normalize-by-median.py -k 20 -C 10 -N 4 -x 3e8 -s norm10k20.kh metagenome-cumulative.fa
	#rm norm10k20.kh #do not need
	#rm metagenome-cumulative.fa #do not need
	# output: metagenome-cumulative.fa.keep

	
	
	#task 2 (velvet)
	#input: metagenome-cumulative.fa.keep
	#requires velvet install
	#velveth assembly 21 metagenome-cumulative.fa.keep
	#velvetg assembly
	# output: assembly/contigs.fa
	

	
}






sub create_cap_workflow {
	my ($self, $assembly, $mgmid, $list_of_read_files) = @_;

	
	
	my $workflow = new AWE::Workflow(
		"pipeline"=> "cap",
		"name"=> "cap",
		"project"=> "cap",
		"user"=> "kbase-user",
		"clientgroups"=> $self->clientgroup,
		"noretry"=> JSON::true,
		"shockhost" => $self->shockurl() || die, # default shock server for output files
		"shocktoken" => $self->shocktoken() || die
	);

	
	
	# app defintions can be found here:
	# https://github.com/wgerlach/Skyport/blob/master/apps.json
	
	
	#testing:
	#my $t0 = $workflow->newTask('app:CAP.test.default');
	#return $workflow;
	
	
	my $t1 = $workflow->newTask('CAP.coverage-bed-reference.default',
									shock_resource($assembly)
									);
	
	
	
	
	my $t2 = $workflow->newTask('Bowtie2.bowtie2-build.default',
									shock_resource($assembly)
									);
	

	
	my @taskgroup3 = ();
	my $t2_id = $t2->taskid();
	for (my $i = 0 ; $i < @{$list_of_read_files} ; $i++) {
		$taskgroup3[$i] = $workflow->newTask('Bowtie2.bowtie2.default',
												shock_resource($list_of_read_files->[$i]),
												task_resource($t2_id, 0), task_resource($t2_id, 1), task_resource($t2_id, 2), task_resource($t2_id, 3), task_resource($t2_id, 4), task_resource($t2_id, 5)  # this line is bowtie database
											);
	}
	
	

	
	
	my @taskgroup4 = ();
	for (my $i = 0 ; $i < @{$list_of_read_files} ; $i++) {
		$taskgroup4[$i] = $workflow->newTask('Samtools.samtools.view',
												task_resource($taskgroup3[$i]->taskid(), 0) ,
												shock_resource($assembly)
											);
	}
	
	
	
	my @taskgroup5 = ();
	for (my $i = 0 ; $i < @{$list_of_read_files} ; $i++) {
		$taskgroup5[$i] = $workflow->newTask('Bedtools.bedtools.bamtobed',
												task_resource($taskgroup4[$i]->taskid(), 0)
											);
	}
	
	
	
	my @taskgroup6 = ();
	for (my $i = 0 ; $i < @{$list_of_read_files} ; $i++) {
		$taskgroup6[$i] = $workflow->newTask('Bedtools.coverageBed.default',
												task_resource($taskgroup5[$i]->taskid(), 0),
												task_resource($t1->taskid(), 0) # bedfile
											);
	}
	
	
	
	my @taskgroup7 = ();
	my @taskgroup7_outputs = ();
	for (my $i = 0 ; $i < @{$list_of_read_files} ; $i++) {
		$taskgroup7[$i] = $workflow->newTask('CAP.get-rpkm.default',
												task_resource($taskgroup6[$i]->taskid(), 0),
												shock_resource($list_of_read_files->[$i])
												);
		$taskgroup7_outputs[$i] = task_resource($taskgroup7[$i]->taskid(), 0);
	}

	
	
	#task 8 (cap)
	#requires all rpkm calculated
	#input: *rpkm, meta.txt
	#python merge.py *rpkm
	
	#requires curl (in cap)
	#curl "http://api.metagenomics.anl.gov/1/annotation/similarity/mgm4566339.3?type=ontology&source=Subsystems" > annotations.txt
	
	#python best-hit.py annotations.txt
	#requires R and dependencies phyloseq, plyr, ggplot, saves output as RData
	#also requires a meta.txt file
	#R < core.R --vanilla
	
	#output: metag.RData
	
	my $t8 = $workflow->newTask('CAP.final.default' ,
									string_resource('MGMID', $mgmid),
									list_resource(\@taskgroup7_outputs)
									#shock_resource($metatxt),
									);

	
	
	return $workflow;
	
}



sub submit_workflow {
	my ($self, $workflow) = @_;
	
	my $debug = 0;
	
	############################################
	# connect to AWE server and check the clients
	my $awe = new AWE::Client($self->aweserverurl, $self->shocktoken, $self->shocktoken, $debug); # second token is for AWE
	unless (defined $awe) {
		die;
	}
	$awe->checkClientGroup($self->clientgroup)==0 || die "no clients in clientgroup found, ".$self->clientgroup." (AWE server: ".$self->aweserverurl.")";

	
	
	print "submit job to AWE server...\n";
	my $json = JSON->new;
	my $submission_result = $awe->submit_job('json_data' => $json->encode($workflow->getHash()));
	unless (defined $submission_result) {
		die "error: submission_result is not defined";
	}
	unless (defined $submission_result->{'data'}) {
		print STDERR Dumper($submission_result);
		exit(1);
	}
	my $job_id = $submission_result->{'data'}->{'id'} || die "no job_id found";
	print "result from AWE server:\n".$json->pretty->encode( $submission_result )."\n";
	return $job_id;
	
	
}


#list metagenome files:
#https://kbase.us/services/communities/download/mgm4566339.3
#https://kbase.us/services/communities/download/mgm4566339.3?file_id=050.1
#stage_name=upload
#node_id
#e.g. 16bc4e39-0ee9-4db7-8f35-05ffbfce07b0
#https://kbase.us/services/communities/download/mgm4566339.3?stage_name=upload


#$ENV{'AWE_SERVER_URL'}="http://10.1.12.14:8001";


#my $test = 'http://shock.metagenomics.anl.gov/node/16bc4e39-0ee9-4db7-8f35-05ffbfce07b0';





my $cap = new CAP('clientgroup' => "docker", "aweserverurl" => "http://140.221.67.149:8001/");


#my $test_contigs = 'http://shock.metagenomics.anl.gov/node/4cfbb8bb-b47d-42b3-b92c-b24b0157796c';
#my $mgmid = "mgm4566339.3";
#my $list_of_read_files = ['http://shock.metagenomics.anl.gov/node/f41a7cbc-e1a8-4f96-a3ed-e5768c959577',
#'http://shock.metagenomics.anl.gov/node/f0ecb62c-16f7-4242-96bb-32306f1131ae',
#'http://shock.metagenomics.anl.gov/node/eba3bcf3-7ebf-4d3b-92d9-79d09fd46772'];



my $test_contigs = 'http://shock.metagenomics.anl.gov/node/660e04ea-8200-4f97-bb35-0b75b458aaea';
my $mgmid = "mgm4566339.3";
my $list_of_read_files = ['http://shock.metagenomics.anl.gov/node/6187d503-94d8-4460-8d81-53be7c5ad7d2', 'http://shock.metagenomics.anl.gov/node/b7bf5ca7-975e-4ef3-9040-2ac9a599d70f', 'http://shock.metagenomics.anl.gov/node/54161cd8-b8ab-4182-b47d-464af0970e51'];



my $workflow_document = $cap->create_cap_workflow($test_contigs, $mgmid, $list_of_read_files);

my $json = JSON->new;
print "AWE workflow:\n".$json->pretty->encode( $workflow_document->getHash() )."\n";



my $job_id = $cap->submit_workflow($workflow_document);




