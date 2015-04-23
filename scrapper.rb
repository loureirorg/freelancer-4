# encoding: utf-8
require 'open-uri'
require 'net/http'
require 'pp'
require 'nokogiri'
require 'yaml'
require 'digest'
require 'csv'

# resume
begin
  itens = YAML::load_file("itens.yaml")
rescue Exception => e
  itens = nil
end

puts "Categories: Begin"
if itens.nil?
  # discover subcategories in SaaS
  # subcategories = {"name": url}
  url = "https://www.digitalmarketplace.service.gov.uk/search?lot=saas&showSubcategories=true"
  doc = Nokogiri::HTML(open(url))
  subcategories = {}
  doc.css('#sheader .category a').each do |item|
    url = item.attributes['href'].value
    name = item.children.text.gsub(/\(.*\)/, '').strip
    subcategories[name] = url
  end

  # for each subcategory, gets a paginated list. For each item of this list, gets the company link
  # itens = [{subcategory: "Collaboration", url: ""}]
  itens = []
  subcategories.each do |name, sub_url|
    offset = 0
    the_end = false
    while ! the_end
      puts "#{name}, offset: #{offset}"
      url = "https://www.digitalmarketplace.service.gov.uk#{sub_url}&max=40&offset=#{offset}"
      doc = Nokogiri::HTML(open(url))
      list = doc.css('.search-result-title a')
      break if list.empty?
      list.each do |item|
        itens << {subcategory: name, url: item.attributes['href'].value}
      end
      offset += 40
    end
  end
  File.open("itens.yaml", "w") { |f| f.write itens.to_yaml }
else
  # resumed itens: we'll generate subcategories
  subcategories = {}
  itens.each do |item|
    subcategories[item[:subcategory]] = ""
  end
end
puts "Categories: End"

puts "Companies: Begin"
# resume
begin
  companies = YAML::load_file("companies.yaml")
rescue Exception => e
  companies = []
end

# some companies are in multiples categories
already_done = {}

# companies = [{subcategory: "Collaboration", listing_url: "http...", name: "Kimcell", subtitle: "Datacenta - DNS Hosting", first_name: "Paul", last_name: "Bateman", phone: "01202 755375", email: "paul.bateman@datacenta.net"}]
resume_pos = companies.count
itens.each_with_index do |item, pos|
  key = Digest::MD5.hexdigest(item[:url])
  if pos < resume_pos
    already_done[key] ||= pos
    next 
  end

  # duplicated
  if already_done.has_key?(key)
    puts "company ##{pos + 1}/#{itens.count}: #{item[:url]} JUMP!"
    companies << nil
    unless companies[already_done[key]][:subcategory].include? item[:subcategory]
      companies[already_done[key]][:subcategory] << item[:subcategory]
    end
  else
    puts "company ##{pos + 1}/#{itens.count}"
    subcategory = item[:subcategory]
    listing_url = "https://www.digitalmarketplace.service.gov.uk#{item[:url]}"
    doc = Nokogiri::HTML(open(listing_url))
    company_name = doc.css('.title header p.context').text.strip
    subtitle = doc.css('.title header h1').text.strip
    full_name = doc.css('.meta div ul li:nth(1)').text.strip
    first_name = full_name.split(" ")[0].to_s
    last_name = full_name.split(" ")[1].to_s
    phone = doc.css('.meta div ul li:nth(2)').text.strip
    email = doc.css('.meta div ul li:nth(3)').text.strip
    companies << {subcategory: [subcategory], listing_url: listing_url, company_name: company_name, subtitle: subtitle, full_name: full_name, first_name: first_name, last_name: last_name, phone: phone, email: email}

    already_done[key] = pos
  end

  if companies.count % 50 == 0
    File.open("companies.yaml", "w") { |f| f.write companies.to_yaml }
  end
end
File.open("companies.yaml", "w") { |f| f.write companies.to_yaml }
puts "Companies: End"

puts "CSV: Begin"
csv = []
sub_names = subcategories.keys.sort
csv << (["Listing URL", "Company Name", "Subtitle", "Full Name", "First Name", "Last Name", "Phone", "Email", "Categories"] + sub_names).to_csv # header
companies.each do |company|
  next if company.nil?
  sub_values = []
  sub_names.each do |name|
    sub_values << (company[:subcategory].include?(name) ? "1" : "")
  end
  csv << ([company[:listing_url], company[:company_name], company[:subtitle], company[:full_name], company[:first_name], company[:last_name], '"' + company[:phone] + '"', company[:email], company[:subcategory].join(", ")] + sub_values).to_csv # header
end
File.open("list.csv", "w") { |f| f.write csv.join }
puts "CSV: End"