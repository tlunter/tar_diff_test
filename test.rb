require 'pry'
require 'zlib'
require 'archive/tar/minitar'

BASE = 'swipely.tar'
NEW  = 'swipely-image.tar'

OUT  = STDOUT

HEADER_UNPACK_FORMAT  = "Z100A8A8A8A12A12A8aZ100A6A2Z32Z32A8A8Z155"

def file_write(read, write, header, size, remainder)
  write.write(header)
  quick_read(read, write, size)
  write.write("\0" * remainder)
end

def skip(read, size)
  if read.respond_to?(:seek)
    read.seek(size, IO::SEEK_CUR)
  else
    read.read(size)
  end
end

def quick_read(read, write, size)
  while size > 0
    bread = read.read([size, 4096].min)
    write.write(bread) if write
    raise UnexpectedEOF if read.eof?
    size -= bread.size
  end
end


def read_entry(io)
  loop do
    return if io.eof?

    data      = io.read(512)
    fields    = data.unpack(HEADER_UNPACK_FORMAT)
    name      = fields[0]
    size      = fields[4].oct
    mtime     = fields[5].oct
    prefix    = fields[15]

    empty = (data == "\0" * 512)
    bytes_skip = (512 - (size % 512)) % 512

    yield data, name, prefix, mtime, size, bytes_skip, empty

    skip(io, bytes_skip) # discard trailing zeros
  end
end

begin
  sgz = File.open("output.tar", 'wb')#Zlib::GzipWriter.new(OUT)

  bgz = File.open(BASE, 'rb')#Zlib::GzipReader.open(BASE)
  base_enumerator = to_enum(:read_entry, bgz)

  ngz = File.open(NEW, 'rb')#Zlib::GzipReader.open(NEW)
  new_enumerator = to_enum(:read_entry, ngz)

  diff_files = 0

  loop do
    begin
      n_header, n_name, n_prefix, n_mtime, n_size, n_remainder, n_empty = new_enumerator.peek
    rescue StopIteration
      puts "Done with new file"
      break
    end

    break if n_empty

    begin
      _, b_name, b_prefix, b_mtime, b_size, b_remainder, b_empty = base_enumerator.peek
    rescue StopIteration
      puts "Done with base file"
      file_write(ngz, sgz, n_header, n_size, n_remainder)
      diff_files += 1
      new_enumerator.next
      next
    end

    break if b_empty

    full_n_name = "#{n_prefix}/#{n_name}"
    full_n_name = full_n_name[1..-1] if full_n_name[0] == "/"

    full_b_name = "#{b_prefix}/#{b_name}"
    full_b_name = full_b_name[1..-1] if full_b_name[0] == "/"

    if (full_n_name < full_b_name)
      file_write(ngz, sgz, n_header, n_size, n_remainder)
      diff_files += 1
      new_enumerator.next
      next
    end

    if (full_b_name < full_n_name)
      skip(bgz, b_size)
      base_enumerator.next
      next
    end

    if (n_mtime != b_mtime) || (n_size != b_size)
      file_write(ngz, sgz, n_header, n_size, n_remainder)
      diff_files += 1
      new_enumerator.next
      next
    end

    skip(ngz, n_size)
    new_enumerator.next
    skip(bgz, b_size)
    base_enumerator.next
  end

  puts diff_files
ensure
  #ngz.close if ngz
  #bgz.close if bgz
  #sgz.close if sgz
end
