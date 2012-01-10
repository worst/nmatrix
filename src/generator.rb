class DTypeInfo < Struct.new(:enum, :sizeof, :sym, :id, :type); end

module Generator
  DTYPES = [
      # dtype enum      sizeof        label/symbol/string   num-class
      [:NM_NONE,        0,            :none,        0,      :none],
      [:NM_BYTE,        :u_int8_t,    :byte,        :b,     :int],
      [:NM_INT8,        :int8_t,      :int8,        :i8,    :int],
      [:NM_INT16,       :int16_t,     :int16,       :i16,   :int],
      [:NM_INT32,       :int32_t,     :int32,       :i32,   :int],
      [:NM_INT64,       :int64_t,     :int64,       :i64,   :int],
      [:NM_FLOAT32,     :float,       :float32,     :f32,   :float],
      [:NM_FLOAT64,     :double,      :float64,     :f64,   :float],
      [:NM_COMPLEX64,   :complex64,   :complex64,   :c64,   :complex],
      [:NM_COMPLEX128,  :complex128,  :complex128,  :c128,  :complex],
      [:NM_RATIONAL32,  :rational32,  :rational32,  :r32,   :rational],
      [:NM_RATIONAL64,  :rational64,  :rational64,  :r64,   :rational],
      [:NM_RATIONAL128, :rational128, :rational128, :r128,  :rational],
      [:NM_ROBJ,        :VALUE,       :object,      :v,     :value],
      [:NM_TYPES,       0,            :dtypes,      0,      :none]
  ].map { |d| DTypeInfo.new(*d) }

  DTYPES_ASSIGN = {
      :complex => { # Assign a complex to:
          :complex  => lambda {|l,r| "((#{l}*)p1)->r = ((#{r}*)p2)->r; ((#{l}*)p1)->i = ((#{r}*)p2)->i;" },
          :float    => lambda {|l,r| "*(#{l}*)p1 = ((#{r}*)p2)->r;" },
          :int      => lambda {|l,r| "*(#{l}*)p1 = ((#{r}*)p2)->r;" },
          :rational => lambda {|l,r| "rb_raise(rb_eNotImpError, \"I don't know how to assign a complex to a rational\");"  },
          :value    => lambda {|l,r| "*(VALUE*)p1 = rb_complex_new(((#{r}*)p2)->r, ((#{r}*)p2)->i);" },
       },
      :float => {
          :complex  => lambda {|l,r| "((#{l}*)p1)->i = 0; ((#{l}*)p1)->r = *(#{r}*)p2;" },
          :float    => lambda {|l,r| "*(#{l}*)p1 = *(#{r}*)p2;" },
          :int      => lambda {|l,r| "*(#{l}*)p1 = *(#{r}*)p2;" },
          :rational => lambda {|l,r| "rb_raise(rb_eNotImpError, \"I don't know how to assign a float to a rational\");" },
          :value    => lambda {|l,r| "*(VALUE*)p1 = rb_float_new(*(#{r}*)p2);" },
      },
      :int => {
          :complex  => lambda {|l,r| "((#{l}*)p1)->i = 0; ((#{l}*)p1)->r = *(#{r}*)p2;" },
          :float    => lambda {|l,r| "*(#{l}*)p1 = *(#{r}*)p2;" },
          :int      => lambda {|l,r| "*(#{l}*)p1 = *(#{r}*)p2;" },
          :rational => lambda {|l,r| "((#{l}*)p1)->d = 1; ((#{l}*)p1)->n = *(#{r}*)p2;" },
          :value    => lambda {|l,r| "*(VALUE*)p1 = INT2NUM(*(#{r}*)p2);" },
      },
      :rational => {
          :complex  => lambda {|l,r| "((#{l}*)p1)->i = 0; ((#{l}*)p1)->r = ((#{r}*)p2)->n / (double)((#{r}*)p2)->d;" },
          :float    => lambda {|l,r| "*(#{l}*)p1 = ((#{r}*)p2)->n / (double)((#{r}*)p2)->d;" },
          :int      => lambda {|l,r| "*(#{l}*)p1 = ((#{r}*)p2)->n / ((#{r}*)p2)->d;" },
          :rational => lambda {|l,r| "((#{l}*)p1)->d = ((#{r}*)p2)->d; ((#{l}*)p1)->n = ((#{r}*)p2)->n;" },
          :value    => lambda {|l,r| "*(VALUE*)p1 = rb_rational_new(((#{r}*)p2)->n, ((#{r}*)p2)->d);" }
      },
      :value => {
          :complex  => lambda {|l,r| "((#{l}*)p1)->r = NUM2REAL(*(VALUE*)p2); ((#{l}*)p1)->i = NUM2IMAG(*(VALUE*)p2);" },
          :float    => lambda {|l,r| "*(#{l}*)p1 = NUM2DBL(*(VALUE*)p2);"},
          :int      => lambda {|l,r| "*(#{l}*)p1 = NUM2DBL(*(VALUE*)p2);"},
          :rational => lambda {|l,r| "((#{l}*)p1)->n = NUM2NUMER(*(VALUE*)p2); ((#{l}*)p1)->d = NUM2DENOM(*(VALUE*)p2);" },
          :value    => lambda {|l,r| "*(VALUE*)p1 = *(VALUE*)p2;"}
      }
  }


  class << self

    def decl spec_name, ary
      a = []
      a << "#{spec_name} {"
      ary.each do |v|
        a << "  #{v.to_s},"
      end
      a << "};"
      a.join("\n") + "\n\n"
    end


    def dtypes_err_functions
      str = <<SETFN
static void TypeErr(void) {
  rb_raise(rb_eTypeError, "illegal operation with this type");
}

SETFN
    end


    def dtypes_set_function_ident dtype_i, dtype_j
      dtype_i[:enum] == :NM_NONE || dtype_j[:enum] == :NM_NONE ? "TypeErr" : "Set_#{dtype_i[:id]}_#{dtype_j[:id]}"
    end

    def dtypes_assign lhs, rhs
      Generator::DTYPES_ASSIGN[ rhs.type ][ lhs.type ].call( lhs.sizeof, rhs.sizeof )
    end


    # Declare a set function for a pair of dtypes
    def dtypes_set_function dtype_i, dtype_j
      str = <<SETFN
static void #{dtypes_set_function_ident(dtype_i, dtype_j)}(size_t n, char* p1, size_t i1, char* p2, size_t i2) {
  for (; n > 0; --n) {
    #{dtypes_assign(dtype_i, dtype_j)}
    p1 += i1; p2 += i2;
  }
}

SETFN
    end


    def dtypes_set_functions_matrix
      ary = []
      DTYPES.each do |i|
        next if i[:enum] == :NM_TYPES
        bry = []
        DTYPES.each do |j|
          next if j[:enum] == :NM_TYPES
          bry << dtypes_set_function_ident(i,j)
        end
        ary << "{ " + bry.join(", ") + " }"
      end
      ary
    end


    def dtypes_set_functions
      ary = []

      ary << dtypes_err_functions

      DTYPES.each do |dtype_i|
        DTYPES.each do |dtype_j|
          begin
            setfn = dtypes_set_function(dtype_i, dtype_j)
            ary << setfn unless setfn =~ /TypeErr/
          rescue NotImplementedError => e
            STDERR.puts "Warning: #{e.to_s}"
          rescue NoMethodError => e
            # do nothing
          end
        end
      end
      ary << ""
      ary << decl("nm_setfunc_t SetFuncs =", dtypes_set_functions_matrix)

      ary.join("\n")
    end


    def dtypes_enum
      decl("enum NMatrix_DTypes", DTYPES.map{ |d| d[:enum].to_s })
    end

    def dtypes_sizeof
      decl("const int nm_sizeof[#{DTYPES.size}] =", DTYPES.map { |d| d[:sizeof].is_a?(Fixnum) ? d[:sizeof] : "sizeof(#{d[:sizeof].to_s})"})
    end

    def dtypes_typestring
      decl("const char *nm_dtypestring[] =", DTYPES.map { |d| "\"#{d[:sym].to_s}\"" })
    end


    def make_file filename, &block
      STDERR.puts "generated #{filename}"
      f = File.new(filename, "w")
      file_symbol = filename.split('.').join('_').upcase

      f.puts "/* Automatically created using generator.rb - do not modify! */"

      f.puts "#ifndef #{file_symbol}\n# define #{file_symbol}\n\n"
      yield f
      f.puts "\n#endif\n\n"
      f.close
    end


    def make_dtypes_c
      make_file "dtypes.c" do |f|
        f.puts dtypes_sizeof
        f.puts dtypes_typestring
      end
    end


    def make_dtypes_h
      make_file "dtypes.h" do |f|
        f.puts dtypes_enum
      end
    end


    def make_dfuncs_c
      make_file "dfuncs.c" do |f|
        f.puts '#include <ruby.h>'
        f.puts '#include "nmatrix.h"' + "\n\n"
        f.puts dtypes_set_functions
      end
    end

  end
end

Generator.make_dtypes_h
Generator.make_dtypes_c
Generator.make_dfuncs_c