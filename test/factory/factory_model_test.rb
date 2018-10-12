# # Copyright © Mapotempo, 2018
# #
# # This file is part of Mapotempo.
# #
# # Mapotempo is free software. You can redistribute it and/or
# # modify since you respect the terms of the GNU Affero General
# # Public License as published by the Free Software Foundation,
# # either version 3 of the License, or (at your option) any later version.
# #
# # Mapotempo is distributed in the hope that it will be useful, but WITHOUT
# # ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# # or FITNESS FOR A PARTICULAR PURPOSE.  See the Licenses for more details.
# #
# # You should have received a copy of the GNU Affero General Public License
# # along with Mapotempo. If not, see:
# # <http://www.gnu.org/licenses/agpl.html>

require 'factory_bot'
require 'logger'

include FactoryBot::Syntax::Methods

def compute_matrice(taille)
  matrice = []
  (0..taille-1).each{ |i|
    tab = []
    (0..taille-1).each{ |j|
      tab << 1 if i != j
      tab << 0 if i == j
    }
    matrice << tab
  }

  matrice
end

class Problem
  attr_accessor :points
  attr_accessor :configuration
  attr_accessor :units
  attr_accessor :matrices
  attr_accessor :services
  attr_accessor :vehicles
end

class Point
  attr_accessor :id
  attr_accessor :matrix_index
  attr_accessor :location

  def initialize(*vals)
    @values = vals
  end
end

class Vehicle
  attr_accessor :id
  attr_accessor :cost_fixed
  attr_accessor :cost_distance_multiplier
  attr_accessor :cost_time_multiplier
  attr_accessor :cost_value_multiplier
  attr_accessor :cost_waiting_time_multiplier
  attr_accessor :cost_late_multiplier
  attr_accessor :matrix_id
  attr_accessor :router_mode
  attr_accessor :duration
  attr_accessor :start_point_id
  attr_accessor :end_point_id
  attr_accessor :rest_ids
  attr_accessor :overall_duration
end  

class Service
  attr_accessor :id
  attr_accessor :skills
  attr_accessor :type
end

class Quantity
  attr_accessor :id
  attr_accessor :unit_id
  attr_accessor :value
end

class Capacities
  attr_accessor :id
  attr_accessor :unit_id
  attr_accessor :limit
  attr_accessor :overload_multiplier
end

class Capacity
  attr_accessor :id
  attr_accessor :unit_id
  attr_accessor :limit
  attr_accessor :overload_multiplier
end

class Activity
  attr_accessor :duration
  attr_accessor :additional_value
  attr_accessor :point_id
  attr_accessor :late_multiplier
  attr_accessor :setup_duration
  attr_accessor :timewindows
end

class Timewindows
  attr_accessor :id
  attr_accessor :start
  attr_accessor :end
  attr_accessor :day_index
end

class Unit
  attr_accessor :id
  attr_accessor :label
  attr_accessor :counting
end

class Shipment
  attr_accessor :id
  attr_accessor :maximum_inroute_duration
  attr_accessor :pickup
  attr_accessor :delivery
end

class Pickup
  attr_accessor :point_id
  attr_accessor :duration
  attr_accessor :late_multiplier
end

class Delivery
  attr_accessor :point_id
  attr_accessor :duration
  attr_accessor :late_multiplier
end

class Route 
  attr_accessor :vehicle_id
  attr_accessor :mission_ids
end

class Relation
  attr_accessor :id
  attr_accessor :type
  attr_accessor :linked_ids
  attr_accessor :linked_vehicle_ids
  attr_accessor :lapse
  attr_accessor :periodicity
end

class Matrice
  attr_accessor :id
  attr_accessor :time
  attr_accessor :distance
  attr_accessor :value
end

class MatriceInit
  attr_accessor :id
  attr_accessor :time
  attr_accessor :distance
  attr_accessor :value
end

class Rest
  attr_accessor :id
  attr_accessor :duration
  attr_accessor :late_multiplier
  attr_accessor :exclusion_cost
end

class Resolution
  attr_accessor :duration
  attr_accessor :iterations_without_improvment
  attr_accessor :initial_time_out
  attr_accessor :time_out_multiplier
end

class Restitution
  attr_accessor :intermediate_solutions
end

class Preprocessing
  attr_accessor :prefer_short_segment
end

class PointLocation
  attr_accessor :id
  attr_accessor :location
end

class VehicleLocation
  attr_accessor :id
  attr_accessor :start_point_id
end

class Range
  attr_accessor :start
  attr_accessor :end
end

class Schedule
  attr_accessor :range_indices
end

class Configuration
  attr_accessor :resolution
  attr_accessor :preprocessing
  attr_accessor :restitution
  attr_accessor :schedule
end

class Polygon
  attr_accessor :type
  attr_accessor :coordinates
end

class Zone
  attr_accessor :id
  attr_accessor :polygon
  attr_accessor :allocations
end

FactoryBot.define do

  sequence(:matrice_id) { |n| "matrix_#{n-1}"}

  factory :matrice do
    id { generate(:matrice_id) }
    time { [
          [0, 1, 1],
          [1, 0, 1],
          [1, 1, 0]
        ] }
  end

  factory :matrice_init do
    transient do 
      taille { }
    end
    id { "matrix_0" }
    time { compute_matrice(taille) }
    distance { compute_matrice(taille) }
  end

  sequence(:id) { |n| "point_#{n-1}"}
  sequence(:matrix_index) { |n| n-1 }

  factory :point do
    id { generate(:id) }
    matrix_index { generate(:matrix_index) }
  end

  factory :pointLocation do
    transient do
      lat { }
      lon { }
    end
    id { generate(:id) }
    location { { lat: lat, lon: lon } }
  end

  sequence(:unit_id) { |n| "unit_#{n-1}"}

  factory :unit do
    id { generate(:unit_id) }
  end

  factory :rest do
    id { 'rest_0' }
    duration { 1 }
  end

  factory :capacities do
    unit_id { "unit_0" }
    overload_multiplier { 0 }
  end

  factory :capacity do
    overload_multiplier { 0 }
  end

  sequence(:vehicle_id) { |n| "vehicle_#{n-1}"}

  factory :vehicle do
    transient do
      limit { }
      limit1 { }
      limit2 { }
      limit3 { }
    end
    id { generate(:vehicle_id) }
    start_point_id { 'point_0'}
    matrix_id { 'matrix_0' }

    factory :vehicle_with_capacity do
      capacities { [attributes_for(:capacity, limit: limit, unit_id: "unit_0")] }
    end 

    factory :vehicle_with_capacities do
      capacities { [{limit: limit1, unit_id: "unit_0"}, {limit: limit2, unit_id: "unit_1"}, {limit: limit3, unit_id: "unit_2"}] }
    end
  end

  factory :vehicleLocation do
    id { generate(:vehicle_id) }
    start_point_id { 'point_0' }
  end

  sequence(:service_id) { |n| "service_#{n}" }
  sequence(:point_id) { |n| "point_#{n}"}

  factory :activity do
    point_id { generate(:point_id) }
  end

  factory :quantity do 
    unit_id { "unit_0" }
  end

  factory :service do
    transient do
      duration {  }
      timewindows { }
      late_multiplier { }
      value { }
      value1 { }
      value2 { }
      empty { }
      empty1 { }
      empty2 { }
      fill { }
      setup_duration { }
      setup_value { }
    end
    id { generate(:service_id) }
    activity { attributes_for(:activity, duration: duration, late_multiplier: late_multiplier, timewindows: timewindows, setup_duration: setup_duration) }

    factory :service_with_capacity do
      quantities { [attributes_for(:quantity, value: value, fill: fill, setup_value: setup_value, empty: empty)] }
    end

    factory :service_with_capacities do
      quantities { [{unit_id: 'unit_0', value: value1, empty: empty1}, {unit_id: 'unit_1', value: value2, empty: empty2}] }
    end
  end

  factory :pickup do
    late_multiplier { 0 }
  end

  factory :delivery do
    late_multiplier { 0 }
  end

 sequence(:shipment_id) { |n| "shipment_#{n-1}" }

  factory :shipment do
    transient do
      pointPickup { }
      timewindowPickup { }
      pointDelivery { }
      timewindowDelivery { }
      durationP { }
      durationD { }
      value { }
      max_inroute_duration { }
    end

    id { generate(:shipment_id) }
    maximum_inroute_duration { max_inroute_duration }
    pickup { attributes_for(:pickup, duration: durationP || 3, point_id: pointPickup, timewindows: timewindowPickup) }
    delivery { attributes_for(:delivery, duration: durationD || 3, point_id: pointDelivery, timewindows: timewindowDelivery) }

    factory :shipment_with_capacity do
      quantities { [attributes_for(:quantity, value: value)] }
    end
  end


  factory :resolution do
    duration { }
  end

  factory :schedule do
  end

  factory :restitution do
    intermediate_solutions { false }
  end

  factory :preprocessing do
  end

  factory :configuration do
    transient do
      duration { }
      iterations_without_improvment { }
      initial_time_out { }
      time_out_multiplier { }
      range_indices { }
      range_date { }
      unavailableDate { }
      unavailableIndice { }
      intermediate_solutions { }
      prefer_short_segment { }
      vehicle_limit { }
      cluster_threshold { }
      traces { }
      geometry { }
      geometry_polyline { }
      max_split_size { }
    end

    resolution { attributes_for(:resolution, duration: duration, iterations_without_improvment: iterations_without_improvment, initial_time_out: initial_time_out, time_out_multiplier:time_out_multiplier, vehicle_limit: vehicle_limit)}
    schedule { attributes_for(:schedule, range_indices: range_indices, range_date: range_date, unavailable_date: unavailableDate, unavailable_indices: unavailableIndice) }
    restitution { attributes_for(:restitution, intermediate_solutions: intermediate_solutions, trace: traces, geometry: geometry, geometry_polyline: geometry_polyline) }
    preprocessing { attributes_for(:preprocessing, prefer_short_segment: prefer_short_segment, cluster_threshold: cluster_threshold, max_split_size: max_split_size) }
  end

  factory :problem do
    transient do
      matrice { }
      point { }
      unit { }
      vehicle { }
      service { }
    end
    matrices { attributes_for_list(:matrice_init, matrice, taille: point) }
    points { attributes_for_list(:point, point) }
    units { attributes_for_list(:unit, unit) }
    rests {  }
    shipments { }
    vehicles { attributes_for_list(:vehicle, vehicle) }
    services { attributes_for_list(:service, service) }
    configuration { attributes_for(:configuration, duration: 100, intermediate_solutions: false, prefer_short_segment: false) }
  end

  factory :polygon do
    type { "Polygon" }
  end

  sequence(:zone_id) { |n| "zone_#{n-1}" }

  factory :zone do
    transient do
      coordinates { }
      allocation { }
    end
    id { generate(:zone_id) }
    polygon { attributes_for(:polygon, coordinates: [coordinates]) }
    allocations { allocation }
  end

end

FactoryBot.rewind_sequences