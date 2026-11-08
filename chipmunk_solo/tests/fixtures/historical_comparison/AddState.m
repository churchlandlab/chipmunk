function sma=AddState(sma,varargin)
s=struct();
for k=1:2:numel(varargin)
 name=varargin{k};
 if strcmp(name,'StateChangeCondition'),name='StateChangeConditions';end
 s.(name)=varargin{k+1};
end
sma.States{end+1}=s;
end
