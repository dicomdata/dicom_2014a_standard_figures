#!/usr/bin/env perl
# Copyright 2014 Michal Špaček <tupinek@gmail.com>

# Pragmas.
use strict;
use warnings;

# Modules.
use Database::DumpTruck;
use Digest::MD5;
use Encode qw(decode_utf8);
use English;
use File::Temp qw(tempfile);
use HTML::TreeBuilder;
use LWP::UserAgent;
use URI;

# Don't buffer.
$OUTPUT_AUTOFLUSH = 1;

# URI of service.
my $base_uri = URI->new('http://medical.nema.org/medical/dicom/2014a/source/docbook/');

# Open a database handle.
my $dt = Database::DumpTruck->new({
	'dbname' => 'data.sqlite',
	'table' => 'data',
});

# Create a user agent object.
my $ua = LWP::UserAgent->new(
	'agent' => 'Mozilla/5.0',
);

# Get base root.
print 'Page: '.$base_uri->as_string."\n";
my @links = get_links($base_uri, sub {
	my $uri = shift;
	if ($uri =~ m/part\d+/ms) {
		return 1;
	}
	return 0;
});
foreach my $link_uri (@links) {

	# Get part number.
	my ($part_num) = $link_uri->as_string =~ m/part(\d+)/ms;
	$part_num = int($part_num);

	# Get figures link.
	my ($figures_uri) = get_links($link_uri, sub {
		my $uri = shift;
		if ($uri =~ m/figures/ms) {
			return 1;
		}
		return 0;
	});

	# Get figures.
	my @svg = get_links($figures_uri, sub {
		my $uri = shift;
		if ($uri =~ m/\.svg/ms) {
			return 1;
		}
		return 0;
	});

	# Insert.
	foreach my $svg_uri (@svg) {
		print "Part $part_num - ".$svg_uri->as_string."\n";
		my $md5 = md5($svg_uri->as_string);
		$dt->insert({
			'Part' => $part_num,
			'SVG_link' => $svg_uri->as_string,
			'MD5' => $md5,
		});
		# TODO Move to begin with create_table().
		$dt->create_index(['MD5'], 'data', 1, 0);
	}
}

# Get root of HTML::TreeBuilder object.
sub get_root {
	my $uri = shift;
	my $get = $ua->get($uri->as_string);
	my $data;
	if ($get->is_success) {
		$data = $get->content;
	} else {
		die "Cannot GET '".$uri->as_string." page.";
	}
	my $tree = HTML::TreeBuilder->new;
	$tree->parse(decode_utf8($data));
	return $tree->elementify;
}

# Get links.
sub get_links {
	my ($uri, $filter_callback) = @_;
	my $root = get_root($uri);
	my @a = $root->find_by_tag_name('a');
	my @links;
	foreach my $a (@a) {
		my $href = $a->attr('href');
		my $link_uri = URI->new($uri->scheme.'://'.
			$uri->host.$href);
		if (! defined $filter_callback 
			|| (defined $filter_callback
			&& $filter_callback->($link_uri->as_string))) {

			push @links, $link_uri;
		}
	}
	return @links;
}

# Get link and compute MD5 sum.
sub md5 {
	my $link = shift;
	my (undef, $temp_file) = tempfile();
	my $get = $ua->get($link, ':content_file' => $temp_file);
	my $md5_sum;
	if ($get->is_success) {
		my $md5 = Digest::MD5->new;
		open my $temp_fh, '<', $temp_file;
		$md5->addfile($temp_fh);
		$md5_sum = $md5->hexdigest;
		close $temp_fh;
		unlink $temp_file;
	}
	return $md5_sum;
}
