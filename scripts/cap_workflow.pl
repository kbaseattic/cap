#!/usr/bin/env perl
package CAP;
use strict;
use warnings;
#use Config::Simple; # for kbase config


use JSON;

use Data::Dumper;


use AWE::Workflow; # includes Shock::Client
use AWE::Task;
use AWE::TaskInput;
use AWE::TaskOutput;

use AWE::Client;

#use Shock::Client; # not clear why I can't use that here ....

1;

sub new {
	my ($class, %h) = @_;
	if (defined($h{'shocktoken'}) && $h{'shocktoken'} eq '') {
		$h{'shocktoken'} = undef;
	}
	my $self = {
		aweserverurl	=> ($ENV{'AWE_SERVER_URL'}  || die "AWE_SERVER_URL not defined"),
		shockurl	=> ($ENV{'SHOCK_SERVER_URL'} || die "SHOCK_SERVER_URL not defined"),
		clientgroup	=> ($ENV{'AWE_CLIENT_GROUP'} || die "AWE_CLIENT_GROUP not defined"),
		shocktoken	=> ($h{'shocktoken'} || die "shocktoken not defined in CAP constructor")
	};
	

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
	my ($self, $assembly, $metatxt, $mgmid, $input_ref) = @_;

	
	
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

	
	
	#my $h = $self->shockurl;
	
	##############################
	# files, assembly and mgm id , meta.txt
	
	#task 1 (cap)
	#input: contigs.fa
	#can be done anytime after assembly but prior to bedtools
	#python coverage-bed-reference.py contigs.fa #produces contigs.fa.bed
	#output: contigs.fa.bed
	my $newtask = undef;
	
	$newtask = $workflow->newTask('app:CAP.coverage-bed-reference.default',
										shock_resource($assembly)
										);
	my $t1 = $newtask->taskid();
	
	
	#task2 (bowtie)
	#input: contigs.fa
	#bowtie2-build contigs.fa assembly
	#output: assembly.*
	
	$newtask = $workflow->newTask('app:Bowtie2.bowtie2-build.default',
									shock_resource($assembly) #task_resource($t1, 0)
									);
	my $t2 = $newtask->taskid();

	
	
	
	
	
	#taskgroup 3 (bowtie)
	#can be done in parallel
	#input: *renamed, assembly.*
	#for x in *renamed; do bowtie2 -x assembly -f $x -S $x.sam; done
	#output: *renamed.sam
	
	my @taskgroup3 = ();
	for (my $i = 0 ; $i < @{$input_ref} ; $i++) {
		$taskgroup3[$i] = $workflow->newTask('app:Bowtie2.bowtie2.default',
												shock_resource($input_ref->[$i]),
												task_resource($t2, 0), task_resource($t2, 1), task_resource($t2, 2), task_resource($t2, 3), task_resource($t2, 4), task_resource($t2, 5)  # this line is bowtie database
											);
	}
	
	
	#taskgroup 4 (cap)
	#requires samtools, can be done in parallel
	#input: *sam
	#for x in *sam; do samtools view -b -t contigs.fa $x -o $x.bam; done
	#output: *sam.bam
	my @taskgroup4 = ();
	for (my $i = 0 ; $i < @{$input_ref} ; $i++) {
		$taskgroup4[$i] = $workflow->newTask('app:Samtools.samtools.default',
												task_resource($taskgroup3[$i]->taskid(), 0) ,
												shock_resource($assembly)
											);
	}
	
	return $workflow;
	
	#taskgroup 5 (cap)
	#requires bedtools, can be done in parallel
	#input: *bam
	#for x in *bam; do bedtools bamtobed -i $x > $x.bed; done
	#output: *.bed
	my @taskgroup5 = ();
	for (my $i = 0 ; $i < @{$input_ref} ; $i++) {
		$taskgroup5[$i] = $workflow->newTask('app:Bedtools.bedtools.bamtobed',
												task_resource($taskgroup4[$i]->taskid(), 0)
											);
	}
	
	
	#taskgroup 6 (cap)
	#requires preceding completed
	#input:  meta*bed, contigs.fa.bed(3)
	#for x in meta*bed; do coverageBed -a $x -b contigs.fa.bed > $x.reads.mapped; done
	#output: .reads.mapped
	my @taskgroup6 = ();
	for (my $i = 0 ; $i < @{$input_ref} ; $i++) {
		$taskgroup6[$i] = $workflow->newTask('app:Bedtools.coverageBed.default',
												task_resource($taskgroup5[$i]->taskid(), 0),
												task_resource($t1, 0) # bedfile
											);
	}
	
	
	#taskgroup 7 (cap)
	#input: *mapped
	#for x in *mapped; do python get-rpkm.py $x; done
	#output: *rpkm
	my @taskgroup7 = ();
	my @taskgroup7_outputs = ();
	for (my $i = 0 ; $i < @{$input_ref} ; $i++) {
		$taskgroup7[$i] = $workflow->newTask('app:CAP.get-rpkm.default',
												task_resource($taskgroup6[$i]->taskid(), 0)
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
	
	$newtask = $workflow->newTask('app:CAP.final.default' ,
									#shock_resource($metatxt),
									string_resource('MGMID', $mgmid),
									list_resource(\@taskgroup7_outputs)
									);

	
	
	return $workflow;
	
}



sub submit_workflow {
	my ($self, $workflow) = @_;
	
	my $debug = 1;
	
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


my $test = 'http://shock.metagenomics.anl.gov/node/16bc4e39-0ee9-4db7-8f35-05ffbfce07b0';

my $test_contigs = 'http://shock.metagenomics.anl.gov/node/4cfbb8bb-b47d-42b3-b92c-b24b0157796c';




my $cap = new CAP('shocktoken' => $ENV{KB_AUTH_TOKEN});
$cap->clientgroup("docker-develop");
$cap->aweserverurl("http://140.221.67.184:8003"); # default is ENV AWE_SERVER_URL


my $assembly = $test;
my $metatxt = "x";
my $mgmid = "someid";
my $input_ref = ['http://shock.metagenomics.anl.gov/node/f41a7cbc-e1a8-4f96-a3ed-e5768c959577',
'http://shock.metagenomics.anl.gov/node/f0ecb62c-16f7-4242-96bb-32306f1131ae',
'http://shock.metagenomics.anl.gov/node/eba3bcf3-7ebf-4d3b-92d9-79d09fd46772'];

my $workflow_document = $cap->create_cap_workflow($test_contigs, undef, $mgmid, $input_ref);

my $json = JSON->new;
print "AWE workflow:\n".$json->pretty->encode( $workflow_document->getHash() )."\n";



my $job_id = $cap->submit_workflow($workflow_document);




