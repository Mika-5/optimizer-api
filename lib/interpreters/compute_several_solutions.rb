# Copyright © Mapotempo, 2018
#
# This file is part of Mapotempo.
#
# Mapotempo is free software. You can redistribute it and/or
# modify since you respect the terms of the GNU Affero General
# Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# Mapotempo is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the Licenses for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with Mapotempo. If not, see:
# <http://www.gnu.org/licenses/agpl.html>
#
module Interpreters
  class Several_solutions

    def self.check_triangle_inequality(matrice)
      @mat = Marshal::load(Marshal.dump(matrice))
      (0..@mat.size-1).each{ |i|
        (0..@mat.size-1).each{ |j|
          (0..@mat[i].size-1).each{ |k|
            if @mat[i][k]+@mat[k][j] < @mat[i][j]
              @mat[i][j] = @mat[i][k]+@mat[k][j]
            end
          }
        }
      }
      return @mat
    end

    def self.generate_matrice(vrp)
      mat = []
      triangleInequality = false
      (0..vrp.matrices[0][:time].size-1).each{ |i|
        tab = []
        (0..vrp.matrices[0][:time][i].size-1).each{ |j|
          if rand(3) == 1
            tab << vrp.matrices[0][:time][i][j] - vrp.matrices[0][:time][i][j]*rand(vrp.resolution_variation_ratio)/100
          else
            tab << vrp.matrices[0][:time][i][j] + vrp.matrices[0][:time][i][j]*rand(vrp.resolution_variation_ratio)/100
          end
        }
        mat << tab if !tab.empty?
      }
      while (0..mat.size-1).any?{ |i| (0..mat[i].size-1).any?{ |j| (0..mat[i].size-1).any? { |k| mat[i][j] > mat[i][k] + mat[k][j] } } }
        mat = check_triangle_inequality(mat)
      end
      vrp.matrices[0][:value] = mat
      vrp.matrices
    end

    def self.compute_vrp_need_matrix(vrp)
      vrp_need_matrix = [
        vrp.need_matrix_time? ? :time : nil,
        vrp.need_matrix_distance? ? :distance : nil,
        vrp.need_matrix_value? ? :value : nil
      ].compact
    end

    def self.compute_need_matrix(vrp, vrp_need_matrix, &block)
      need_matrix = vrp.vehicles.collect{ |vehicle| [vehicle, vehicle.dimensions] }.select{ |vehicle, dimensions|
        dimensions.find{ |dimension|
          vrp_need_matrix.include?(dimension) && (vehicle.matrix_id.nil? || vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }.send(dimension).nil?) && vehicle.send('need_matrix_' + dimension.to_s + '?')
        }
      }

      if need_matrix.size > 0
        points = vrp.points.each_with_index.collect{ |point, index|
          point.matrix_index = index
          [point.location.lat, point.location.lon]
        }
        vrp.vehicles.select{ |v| v[:start_point] && v[:start_point] != nil}.each{ |v|
          v[:start_point][:matrix_index] = vrp[:points].find{ |p| p.id == v[:start_point][:id] }[:matrix_index]
        }
        vrp.vehicles.select{ |v| v[:end_point] && v[:end_point] != nil}.each{ |v|
          v[:end_point][:matrix_index] = vrp[:points].find{ |p| p.id == v[:end_point][:id] }[:matrix_index]
        }

        uniq_need_matrix = need_matrix.collect{ |vehicle, dimensions|
          [vehicle.router_mode.to_sym, dimensions | vrp_need_matrix, vehicle.router_options]
        }.uniq

        i = 0
        id = 0
        uniq_need_matrix = Hash[uniq_need_matrix.collect{ |mode, dimensions, options|
          block.call(nil, i += 1, uniq_need_matrix.size, 'compute matrix', nil, nil, nil) if block
          # set vrp.matrix_time and vrp.matrix_distance depending of dimensions order
          matrices = OptimizerWrapper.router.matrix(OptimizerWrapper.config[:router][:url], mode, dimensions, points, points, options)
          m = Models::Matrix.create({
            id: 'm' + (id+=1).to_s,
            time: (matrices[dimensions.index(:time)] if dimensions.index(:time)),
            distance: (matrices[dimensions.index(:distance)] if dimensions.index(:distance)),
            value: (matrices[dimensions.index(:value)] if dimensions.index(:value))
          })
          vrp.matrices += [m]
          [[mode, dimensions, options], m]
        }]

        uniq_need_matrix = need_matrix.collect{ |vehicle, dimensions|
          vehicle.matrix_id = vrp.matrices.find{ |matrix| matrix == uniq_need_matrix[[vehicle.router_mode.to_sym, dimensions | vrp_need_matrix, vehicle.router_options]] }.id
        }
      end

      vrp
    end

    def self.generate_service_vrp(service_vrp, i)
      return_service_vrp = service_vrp
      vrp = return_service_vrp[:vrp]
      if vrp.matrices.size == 0
        vrp_need_matrix = compute_vrp_need_matrix(return_service_vrp[:vrp])
        return_service_vrp[:vrp] = compute_need_matrix(vrp, vrp_need_matrix)
      end

      if i == 0
        return_service_vrp[:vrp].matrices[0][:value] = vrp.matrices[0][:time]
      else
        return_service_vrp[:vrp].matrices = generate_matrice(vrp)
      end

      (0..return_service_vrp[:vrp].vehicles.size-1).each{ |j|
        return_service_vrp[:vrp].vehicles[j][:cost_time_multiplier] = 0
        return_service_vrp[:vrp].vehicles[j][:cost_distance_multiplier] = 0
        return_service_vrp[:vrp].vehicles[j][:cost_value_multiplier] = 1
      }
      return_service_vrp[:vrp].id = i

      return_service_vrp
    end

    def self.expand(services_vrps)
      service_vrp = []

      if services_vrps[0][:vrp][:resolution_all_heuristic]
        (0..6).each{ |i|
          service_vrp[i] = generate_service_vrp_for_test(Marshal::load(Marshal.dump(services_vrps[0])), i)
        }
      end

      if services_vrps[0][:vrp][:resolution_several_solutions]
        service_vrp[0] = generate_service_vrp(Marshal::load(Marshal.dump(services_vrps[0])), 0)
        (1..services_vrps[0][:vrp][:resolution_several_solutions]).each{ |i|
          service_vrp[i] = generate_service_vrp(Marshal::load(Marshal.dump(service_vrp[0])), i)
        }
      end

      service_vrp
    end

  end
end
