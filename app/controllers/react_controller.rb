# frozen_string_literal: true

class ReactController < ApplicationController
  def index
    render html: params.inspect
  end
end
