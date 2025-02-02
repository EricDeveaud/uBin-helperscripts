
# The MIT License (MIT)
# Copyright (c) 2016 Alexander J Probst

# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require "trollop"

opts=Trollop::options do
  banner <<-EOS

  This is a script to determine the single copy genes in a protein file against a given database. Only stringent matches that span at least 50% of the target are considered.

Usage: scg_search.rb [options]
where options are:
EOS
  opt :usearch, "full path to usearch software", :type => :string, :required => true
  opt :proteins, "input file is a fasta file consisting of amino acid sequences", :type => :string, :required => true
  opt :database, "protein database in fasta format", :type => :string, :required => true
  opt :scgs, "protein file in fasta format that is part of the database file and that contains only the single copy genes", :type => :string, :required => true
  opt :lookup, "tab-delimited lookup file for database, with protein ID as column 1 and single copy gene ID as column 2", :type => :string, :required => true
end

us = opts[:usearch]

input_file = opts[:proteins]
output_dir = File.dirname(input_file)

datab = opts[:database]
db_all = File.dirname(input_file) + "/all_prot.udb"
puts "database name of all proteins is #{datab}"

db_name = opts[:scgs]
puts "database name of SCGs is #{db_name}"

db_lookup = opts[:lookup]
puts "database lookup is #{db_lookup}"

#build databases
full_db = system "#{us} -makeudb_ublast #{datab} -output #{db_all}"
abort "makeblastdb did not work for #{datab}, please check your input file" unless full_db

# find SCG candidates
puts "finding SCG candidates..."
input_blast_database = system "#{us} -makeudb_ublast #{input_file} -output #{input_file}.udb"
input_blast_out = File.join(output_dir,File.basename(input_file) + ".findSCG.b6")
abort "makeblastdb did not work for #{input_file}, please check your input file" unless input_blast_database
input_blast_ok = system "#{us} -ublast #{db_name} -db #{input_file}.udb -evalue 0.01 -threads 6 -userout #{input_blast_out} -userfields query+target+id+alnlen+ql+tl+mism+opens+qlo+qhi+tlo+thi+evalue+bits"
system "rm #{input_file}.udb "
abort "blast did not work, please check your input file." unless input_blast_ok

input_blast_out_whitelist = File.join(output_dir,File.basename(input_file) + ".findSCG.b6.whitelist")
system "awk '{print$2}' #{input_blast_out} | sort -u > #{input_blast_out_whitelist}"
scg_candidates = File.join(output_dir,File.basename(input_file) + ".scg.candidates.faa")
system "pullseq -i #{input_file} -n #{input_blast_out_whitelist} > #{scg_candidates}"
system "rm #{input_blast_out_whitelist}"

# verify SCGs by blasting against all proteins of all genomes
puts "verifying selected SCGs..."
db_blast_out = File.join(output_dir,File.basename(input_file) + ".all.b6")
db_blast_ok = system "#{us} -ublast #{scg_candidates} -db #{db_all} -evalue 0.00001 -maxhits 1 -threads 6 -userout #{db_blast_out} -userfields query+target+id+alnlen+ql+tl+mism+opens+qlo+qhi+tlo+thi+evalue+bits"
abort "verifying blast did not work" unless db_blast_ok
system "rm #{db_all}"
puts "starting annotations of single copy cogs..."

# Read db_lookup
lookup_h = {}
File.open(db_lookup).each do |line|
  sbj, annotation = line.chomp.split
  lookup_h[sbj]=annotation
end

# now compare and print
File.open(File.join(output_dir,File.basename(input_file)+".scg"), "w") do |file|
  File.open(db_blast_out).each do |line|
    next if line =~ /^#/
    line.chomp!
    temp = line.split(/\t/)
    query, sbjct = temp[0], temp[1]
    aln_len, sbjct_len = temp[3], temp[5] 
    if lookup_h[sbjct] && aln_len > (sbjct_len*0.5)
      file.puts "#{query.split[0]}\t#{lookup_h[sbjct]}"
    end
  end
end

puts "successfully finished"


