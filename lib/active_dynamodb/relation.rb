module ActiveDynamoDB
  class Relation
    #
    # Filters/Relations
    #
    # Model.where(field: val).all
    # Model.where(field1:val,field2:val).each
    # Model.where(field1:val).where(field2:val).each
    # Model.where(field: val).first
    # Model.where(field: val).last
    # Model.where(field).between(3,5).all
    # Model.where(field).is_null.count
    #
    EndpointList=%w(each all first delete_all destroy_all count)
    FilterList=%w(where begins_with between contains does_not_contain equals greater_than gte in is_null less_than lte not_equal_to not_null)
    def initialize the_class,association_items,related_obj=nil,association_entry=nil
      @the_class=the_class
      @filters=[]
      @association_items=association_items
      @related_obj=related_obj
      @association_entry=association_entry
    end
    def << val
      #
      # In this example:
      #   class User < ActiveDynamoDB
      #     has_many :sessions, inverse_of: :user
      #   end
      #   class Session < ActiveDynamoDB
      #     belongs_to :user, inverse_of: :sessions
      #   end
      #
      # Then calling:
      #   user.sessions<<val # val is a session in this case
      # Will actually do (if val's to us is a single relation):
      #   user.sessions<<val
      #   val.user_id=user.sessions.related_obj.id
      # Will actually do (if val's to us is a multiple relation):
      #   val.add_or_assign(user.id,:user)
      #   This does:
      #     if :user association in 'val' is a single:
      #       val.user_id=user.id
      #     if :user association in 'val' is a multiple:
      #       val.users_ids<<user.id
      #
      # (self is Relation of user)
      #
      ret=self.attach(val)
      # val.send("#{@association_entry[:inverse_of]}_id=",self.related_obj.id) if @association_entry[:inverse_of]
      raise ObjectIsNotPeristed unless self.related_obj.persisted?
      val.send("add_or_assign",self.related_obj.id,@association_entry[:inverse_of]) if @association_entry[:inverse_of]
      ret
    end
    def remove_stale_associations
      @related_obj.remove_stale_associations @association_entry[:association_name]
    end

    def each &proc
      result_items=follow_filters(@association_items)
      result_items.each do |item|
        obj=@the_class.new
        obj.load_from_item item
        proc.call obj
      end
      self
    end
    def count
      result_items=follow_filters(@association_items)
      result_items.count
    end
    def size
      count
    end
    def all
      ret=[]
      self.each do |item|
        ret<<item
      end
      ret
    end
    def delete_all
      cnt=0
      result_items=follow_filters(@association_items)
      result_items.each do |item|
        item.delete
        cnt+=1
      end
      cnt
    end
    def destroy_all
      cnt=0
      result_items=follow_filters(@association_items)
      result_items.each do |item|
        obj=@the_class.new
        obj.load_from_item item
        obj.destroy
        cnt+=1
      end
      cnt
    end
    def first
      item=follow_filters(@association_items).first
      return nil if item.nil?
      obj=@the_class.new
      obj.load_from_item item
      obj
    end
    def attach obj
      raise ObjectIsNotPeristed unless obj.persisted?
      raise InvalidRelationshipType if @association_entry[:type]!=:multiple
      list=@related_obj.send(@association_entry[:attribute_name])
      list=[] if list.nil?
      list<<obj.id
      ret=@related_obj.send("#{@association_entry[:attribute_name]}=",list)
      ret
    end
    def detach obj
      raise InvalidRelationshipType if @association_entry[:type]!=:multiple
      list=@related_obj.send(@association_entry[:attribute_name])
      list=[] if list.nil?
      list.delete obj.id
      ret=@related_obj.send("#{@association_entry[:attribute_name]}=",list)
      ret
    end
    def method_missing(id,*args)
      if FilterList.include? id.to_s
        @filters<<{filter:id,args:args}
      else
        super
      end
      self
    end
    def related_obj
      @related_obj
    end

    private
    def follow_filters items
      @filters.each do |filter|
        items=items.send(filter[:filter],*filter[:args])
      end
      items
    end
    def add_or_assign obj_id,method
      association=self.class.association_list[method]
      raise InvalidAssociation if association.nil?
      if association[:type]==:single
        self.send("#{method}_id",obj_id)
      elsif association[:type]==:multiple
        if self.send("#{method}_ids").nil?
          self.send("#{method}_ids",[obj_id])
        else
          self.send("#{method}_ids") << obj_id
        end
      else
        raise InvalidRelationshipType
      end
    end
  end
  module RelationSupport
    def method_missing(id, *args, &proc)
      return scoped.send(id,*args,&proc) if Relation::FilterList.include?(id.to_s)
      return scoped.send(id,*args,&proc) if Relation::EndpointList.include?(id.to_s)
      super
    end
    def scoped
      Relation.new self,dynamodb_table.items,self,{type: :none}
    end
  end
end
