#!ruby

require 'uri'
require 'noms/command/urinion/data'

class NOMS

end

class NOMS::Command

end

class NOMS::Command::URInion

    def self.parse(url)
        case url
        when /^data/
            NOMS::Command::URInion::Data.parse(url)
        else
            URI.parse(url)
        end
    end

end
